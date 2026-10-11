import Accelerate
import Foundation

/// Comparison-only edge semantics. These results do not enable production training.
enum ReferenceTrainingEdgeCases {
    enum EdgeError: Error, Equatable {
        case invalidShape, nonFinite, invalidConfiguration, unsupportedSingletonShape
        case indefiniteCovariance, decomposition(Int32), numericalFailure, diagonalBudgetExhausted
        case requiresNonemptyInputs, requiresEmptySharedSelection
    }
    struct PCAResult {
        let eigenvalues: [Double]
        let basis: [[Double]]
        let selectedIndices: [Int]
    }
    struct RepairedCanonicalResult {
        let fit: ReferenceCanonicalTraining.Fit
        let diagonalAdditions: Int
        let repairedWithin: [[Double]]
    }
    /// Deliberately preserves the vendor's partial empty state separately from valid distributions.
    struct EmptySharedPoolingState: Equatable {
        let counts: [Double]
        let mean: [Double]
        let retainedCovariance: [[Double]]
        let updateTime: UInt32
        let isEmpty: Bool
    }

    static func singletonStatistics(featureRows: [[Double]], coordinates: [Int]) throws -> ReferenceTrainingStatistics.Statistics {
        guard featureRows.count == 1, featureRows[0].count == 1 else { throw EdgeError.unsupportedSingletonShape }
        guard coordinates == [0] else { throw EdgeError.invalidShape }
        guard featureRows[0][0].isFinite else { throw EdgeError.nonFinite }
        return .init(average: [featureRows[0][0]], covariance: [[0]], epochCounts: [1])
    }

    /// Retains zero roots. Negative roots are rejected by OUR PSD support boundary;
    /// the vendor eig_sym routine itself does not establish that restriction.
    static func singularPCA(covariance: [[Double]], classCount: Int) throws -> PCAResult {
        let eigenbasis = try psdEigenbasis(covariance: covariance)
        return .init(eigenvalues: eigenbasis.eigenvalues, basis: eigenbasis.basis,
                     selectedIndices: try pcaSelectedIndices(descendingEigenvalues: eigenbasis.eigenvalues,
                                                            classCount: classCount))
    }

    /// Shared PSD eigensolver stage; rank selection happens after low-epoch clipping.
    static func psdEigenbasis(covariance: [[Double]]) throws -> ReferenceGaussianPipeline.Eigenbasis {
        let size = covariance.count
        guard size > 0, size <= 70, covariance.allSatisfy({ $0.count == size }) else { throw EdgeError.invalidShape }
        guard covariance.allSatisfy({ $0.allSatisfy(\.isFinite) }) else { throw EdgeError.nonFinite }
        for row in 0..<size {
            for column in 0..<row where covariance[row][column] != covariance[column][row] { throw EdgeError.invalidShape }
        }
        let leaf: ReferenceNumericalLeaves.Eigenbasis
        do {
            leaf = try ReferenceNumericalLeaves.eigenbasis(
                columnMajor: (0..<size).flatMap { column in covariance.map { $0[column] } },
                dimension: size, method: .divideAndConquer, maximumDimension: 70)
        } catch ReferenceNumericalLeaves.Failure.solverFailed(let codes) {
            throw EdgeError.decomposition(codes.last ?? -1)
        } catch {
            throw EdgeError.numericalFailure
        }
        let values = leaf.ascendingValues
        let vectors = leaf.columnMajorVectors
        guard values.allSatisfy({ $0 >= 0 }) else { throw EdgeError.indefiniteCovariance }
        let roots = Array(values.reversed())
        var basis = Array(repeating: Array(repeating: 0.0, count: size), count: size)
        for column in 0..<size {
            let source = size - column - 1
            let largest = (0..<size).max { abs(vectors[source * size + $0]) < abs(vectors[source * size + $1]) }!
            let sign = vectors[source * size + largest] < 0 ? -1.0 : 1.0
            for row in 0..<size { basis[row][column] = sign * vectors[source * size + row] }
        }
        return .init(eigenvalues: roots, basis: basis)
    }

    /// runPCA rank after optional eigenpair clipping. Exact zero roots are kept;
    /// all-zero spectra produce unordered percentages and an empty selection.
    static func pcaSelectedIndices(descendingEigenvalues roots: [Double], classCount: Int) throws -> [Int] {
        guard !roots.isEmpty, roots.count <= 70, classCount >= 2,
              classCount - 1 <= roots.count else { throw EdgeError.invalidConfiguration }
        guard roots.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw EdgeError.indefiniteCovariance }
        guard zip(roots, roots.dropFirst()).allSatisfy({ $0 >= $1 }) else { throw EdgeError.invalidShape }
        let total = roots.reduce(0, +)
        guard total.isFinite else { throw EdgeError.numericalFailure }
        var cumulative = 0.0
        var selected = [Int]()
        for (index, value) in roots.enumerated() {
            // The binary computes scalar100 * root then divides by sum.
            cumulative += 100 * value / total
            if cumulative <= 99 { selected.append(index) }
        }
        if !selected.isEmpty && selected.count < classCount { selected = Array(0..<(classCount - 1)) }
        return selected
    }

    /// Uses the traced 1e-10 diagonal addition, but an explicit caller budget replaces
    /// the vendor's unbounded retry. No changed input is hidden from the caller.
    static func boundedCanonical(within: [[Double]], between: [[Double]], residualDegreesOfFreedom: Double,
                                 directions: Int, maximumDiagonalAdditions: Int) throws -> RepairedCanonicalResult {
        guard maximumDiagonalAdditions >= 0, maximumDiagonalAdditions <= 10_000 else { throw EdgeError.invalidConfiguration }
        var repaired = within
        for count in 0...maximumDiagonalAdditions {
            do {
                let fit = try ReferenceCanonicalTraining.fit(within: repaired, between: between,
                    residualDegreesOfFreedom: residualDegreesOfFreedom, directions: directions)
                return .init(fit: fit, diagonalAdditions: count, repairedWithin: repaired)
            } catch ReferenceCanonicalTraining.InputError.singularWithinScatter {
                guard count < maximumDiagonalAdditions else { throw EdgeError.diagonalBudgetExhausted }
                for index in repaired.indices { repaired[index][index] += 1e-10 }
            }
        }
        throw EdgeError.diagonalBudgetExhausted
    }

    static func emptySharedPooling(_ first: ReferenceGaussianPooling.Distribution,
                                   _ second: ReferenceGaussianPooling.Distribution,
                                   useFirstUpdateTime: Bool) throws -> EmptySharedPoolingState {
        // Reuse established shape/finite validation. Only the specifically unresolved
        // empty-selection error is handled here; all other errors are propagated.
        do {
            _ = try ReferenceGaussianPooling.combine(first, second, useFirstUpdateTime: useFirstUpdateTime)
            throw EdgeError.requiresEmptySharedSelection
        } catch ReferenceGaussianPooling.PoolingError.noSharedSupportedFeatures {
            guard first.counts.max()! >= 2, second.counts.max()! >= 2 else { throw EdgeError.requiresNonemptyInputs }
            let base = first.counts.min()! >= second.counts.min()! ? first : second
            let time = useFirstUpdateTime ? first.updateTime : (first.updateTime &+ second.updateTime) >> 1
            return .init(counts: [], mean: [], retainedCovariance: base.covariance, updateTime: time, isEmpty: true)
        }
    }
}
