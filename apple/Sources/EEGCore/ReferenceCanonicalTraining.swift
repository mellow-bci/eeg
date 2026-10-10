import Accelerate
import Foundation

/// Comparison-only, nonsingular MANOVA arithmetic reconstructed from
/// manova1Cov 0x100b49b04. Explicit scatter matrices avoid guessing the still
/// incomplete epoch extraction, class pooling, PCA selection or Bartlett path.
enum ReferenceCanonicalTraining {
    enum InputError: Error, Equatable {
        case invalidShape, nonFinite, asymmetric, invalidDegreesOfFreedom
        case singularWithinScatter, decomposition(Int32), numericalFailure
    }
    struct Fit: Sendable {
        /// Descending roots of H v = lambda E v, including zero/negative roots.
        let eigenvalues: [Double]
        /// Input features in rows, canonical directions in columns.
        /// diag(B' E B)/(N-K) is one after final normalization.
        let basis: [[Double]]
        let whitenedBetween: [[Double]]
    }

    /// runPCA 0x100b47ac8 uses percentages, cumulative sum and find <=99.
    /// Its zero-selection branch clears the PCA matrix (not a forced minimum).
    /// If 0<count<classCount, it takes the first classCount-1 columns; otherwise
    /// it takes the found indices. Positive descending roots are our boundary.
    static func pcaSelectedIndices(descendingEigenvalues: [Double], classCount: Int) throws -> [Int] {
        guard !descendingEigenvalues.isEmpty, descendingEigenvalues.count <= 70,
              classCount >= 2, classCount - 1 <= descendingEigenvalues.count else {
            throw InputError.invalidShape
        }
        guard descendingEigenvalues.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw InputError.nonFinite
        }
        guard zip(descendingEigenvalues, descendingEigenvalues.dropFirst()).allSatisfy({ $0 >= $1 }) else {
            throw InputError.invalidShape
        }
        let sum = descendingEigenvalues.reduce(0, +)
        guard sum.isFinite, sum > 0 else { throw InputError.numericalFailure }
        var cumulative = 0.0, selected: [Int] = []
        for (index, value) in descendingEigenvalues.enumerated() {
            cumulative += 100 * value / sum
            if cumulative <= 99 { selected.append(index) }
        }
        guard !selected.isEmpty else { return [] }
        return selected.count < classCount ? Array(0..<(classCount - 1)) : selected
    }

    /// Strict SPD branch only. Vendor singular-matrix jitter and Bartlett
    /// significance selection are deliberately not approximated here.
    /// Our choices: LAPACK dsyev, canonical sign and dimension limit 70.
    static func fit(within: [[Double]], between: [[Double]],
                    residualDegreesOfFreedom: Double, directions: Int) throws -> Fit {
        let size = within.count
        guard size > 0, size <= 70, directions > 0, directions <= size,
              within.allSatisfy({ $0.count == size }), between.count == size,
              between.allSatisfy({ $0.count == size }) else { throw InputError.invalidShape }
        guard residualDegreesOfFreedom.isFinite, residualDegreesOfFreedom > 0 else {
            throw InputError.invalidDegreesOfFreedom
        }
        guard within.flatMap({ $0 }).allSatisfy(\.isFinite),
              between.flatMap({ $0 }).allSatisfy(\.isFinite) else { throw InputError.nonFinite }
        for row in 0..<size { for column in 0..<row {
            guard within[row][column] == within[column][row],
                  between[row][column] == between[column][row] else { throw InputError.asymmetric }
        } }
        // E = R' R. Lower L = R' is used for equivalent triangular solves.
        var lower = Array(repeating: Array(repeating: 0.0, count: size), count: size)
        for row in 0..<size { for column in 0...row {
            var value = within[row][column]
            for inner in 0..<column { value -= lower[row][inner] * lower[column][inner] }
            if row == column {
                guard value > 0, value.isFinite else { throw InputError.singularWithinScatter }
                lower[row][column] = sqrt(value)
            } else { lower[row][column] = value / lower[column][column] }
        } }
        // W = R'^-1 H R^-1; vendor averages W and W' before eig_sym.
        var inverseLower = Array(repeating: Array(repeating: 0.0, count: size), count: size)
        for column in 0..<size { for row in 0..<size {
            var value = row == column ? 1.0 : 0.0
            for inner in 0..<row { value -= lower[row][inner] * inverseLower[inner][column] }
            inverseLower[row][column] = value / lower[row][row]
        } }
        var left = Array(repeating: Array(repeating: 0.0, count: size), count: size)
        for row in 0..<size { for column in 0..<size {
            var value = 0.0
            for inner in 0..<size { value += inverseLower[row][inner] * between[inner][column] }
            left[row][column] = value
        } }
        var whitened = Array(repeating: Array(repeating: 0.0, count: size), count: size)
        for row in 0..<size { for column in 0..<size {
            var value = 0.0
            for inner in 0..<size { value += left[row][inner] * inverseLower[column][inner] }
            whitened[row][column] = value
        } }
        for row in 0..<size { for column in 0..<row {
            let value = 0.5 * (whitened[row][column] + whitened[column][row])
            whitened[row][column] = value; whitened[column][row] = value
        } }
        var n = __LAPACK_int(size), lda = n, info: __LAPACK_int = 0
        var vectors = (0..<size).flatMap { column in whitened.map { $0[column] } }
        var roots = Array(repeating: 0.0, count: size)
        var job: Int8 = 86, triangle: Int8 = 85
        var query = [0.0], workspaceSize: __LAPACK_int = -1
        dsyev_(&job, &triangle, &n, &vectors, &lda, &roots, &query, &workspaceSize, &info)
        guard info == 0 else { throw InputError.decomposition(info) }
        guard query[0].isFinite, query[0] >= 1, query[0] <= Double(Int32.max) else {
            throw InputError.numericalFailure
        }
        workspaceSize = __LAPACK_int(ceil(query[0]))
        var workspace = Array(repeating: 0.0, count: Int(workspaceSize))
        dsyev_(&job, &triangle, &n, &vectors, &lda, &roots, &workspace, &workspaceSize, &info)
        guard info == 0 else { throw InputError.decomposition(info) }
        guard roots.allSatisfy(\.isFinite), vectors.allSatisfy(\.isFinite) else {
            throw InputError.numericalFailure
        }
        var basis = Array(repeating: Array(repeating: 0.0, count: directions), count: size)
        for column in 0..<directions {
            let source = size - 1 - column
            // B = R^-1 U = L'^-1 U.
            for row in (0..<size).reversed() {
                var value = vectors[source * size + row]
                for inner in (row + 1)..<size { value -= lower[inner][row] * basis[inner][column] }
                basis[row][column] = value / lower[row][row]
            }
            var variance = 0.0
            for row in 0..<size { for inner in 0..<size {
                variance += basis[row][column] * within[row][inner] * basis[inner][column]
            } }
            let scale = sqrt(variance / residualDegreesOfFreedom)
            guard scale.isFinite, scale > 0 else { throw InputError.numericalFailure }
            let largest = (0..<size).max { abs(basis[$0][column]) < abs(basis[$1][column]) }!
            let sign = basis[largest][column] < 0 ? -1.0 : 1.0
            for row in 0..<size { basis[row][column] *= sign / scale }
        }
        guard basis.flatMap({ $0 }).allSatisfy(\.isFinite) else { throw InputError.numericalFailure }
        return Fit(eigenvalues: Array(roots.reversed().prefix(directions)),
                   basis: basis, whitenedBetween: whitened)
    }
}
