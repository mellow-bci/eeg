import Accelerate
import Foundation

/// Comparison-only LAPACK leaves from numerical-leaves-20261011.
/// The platform LAPACK implementation can differ from the vendor-linked build.
enum ReferenceNumericalLeaves {
    enum Failure: Error { case invalidInput, resourceLimit, solverFailed([Int32]), nonfiniteOutput }
    enum Method: Equatable { case divideAndConquer, standard }
    struct Attempt: Equatable { let method: Method; let info: Int32 }
    struct Eigenbasis {
        let ascendingValues: [Double]
        /// Columns are eigenvectors. No independent sign normalization applied.
        let columnMajorVectors: [Double]
        let attempts: [Attempt]
    }
    struct Workspace: Equatable { let doubles: Int; let integers: Int }
    static func workspace(dimension: Int, method: Method, maximumDimension: Int) throws -> Workspace {
        // Independent resource policy protects arithmetic/allocation, not a vendor maximum.
        guard maximumDimension > 0, maximumDimension <= 4096,
              dimension > 0, dimension <= maximumDimension else { throw Failure.resourceLimit }
        switch method {
        case .divideAndConquer: return .init(doubles: 4 * dimension * dimension + 12 * dimension + 2, integers: 15 * dimension + 9)
        case .standard: return .init(doubles: 3 * max(3 * dimension, 2) - 3, integers: 0)
        }
    }
    /// Both traced leaves consume the UPPER triangle. Lower values are not
    /// silently averaged into it. Exact symmetry is not a solver precondition.
    static func eigenbasis(columnMajor: [Double], dimension: Int, method: Method,
                           maximumDimension: Int) throws -> Eigenbasis {
        _ = try workspace(dimension: dimension, method: method, maximumDimension: maximumDimension)
        guard columnMajor.count == dimension * dimension,
              columnMajor.allSatisfy({ $0.isFinite }) else { throw Failure.invalidInput }
        var attempts: [Attempt] = []
        let methods: [Method] = method == .divideAndConquer ? [.divideAndConquer, .standard] : [.standard]
        for current in methods {
            let sizes = try workspace(dimension: dimension, method: current, maximumDimension: maximumDimension)
            var matrix = columnMajor // fallback starts from original input, as copied in each leaf
            var values = [Double](repeating: 0, count: dimension)
            var doubles = [Double](repeating: 0, count: sizes.doubles)
            var n = Int32(dimension), lda = Int32(dimension), info: Int32 = 0
            var lwork = Int32(sizes.doubles), job: Int8 = 86, upper: Int8 = 85
            if current == .divideAndConquer {
                var integers = [Int32](repeating: 0, count: sizes.integers)
                var liwork = Int32(sizes.integers)
                dsyevd_(&job, &upper, &n, &matrix, &lda, &values, &doubles, &lwork, &integers, &liwork, &info)
            } else {
                dsyev_(&job, &upper, &n, &matrix, &lda, &values, &doubles, &lwork, &info)
            }
            attempts.append(.init(method: current, info: info))
            if info == 0 {
                guard values.allSatisfy({ $0.isFinite }), matrix.allSatisfy({ $0.isFinite }) else { throw Failure.nonfiniteOutput }
                return .init(ascendingValues: values, columnMajorVectors: matrix, attempts: attempts)
            }
        }
        throw Failure.solverFailed(attempts.map(\.info))
    }
}
