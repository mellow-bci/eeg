import Foundation

/// Comparison-only princompMultiClass eigenpair clipping, finite counts >=2.
/// Never guesses ARM unsigned conversion for negative or exceptional inputs.
enum ReferencePCALowEpoch {
    enum InputError: Error, Equatable {
        case invalidShape, unsupportedCount, invalidSpectrum
    }
    struct Result {
        let eigenvalues: [Double]
        let basis: [[Double]]
        let scratchCounts: [Double]
        let wasClipped: Bool
        var retainedCount: Int { eigenvalues.count }
    }

    /// Eigenpairs are already in descending order. Input features occupy rows.
    static func apply(counts: [Double], descendingEigenvalues: [Double],
                      basis: [[Double]]) throws -> Result {
        let dimension = counts.count
        guard dimension > 0, dimension <= 70,
              descendingEigenvalues.count == dimension, basis.count == dimension,
              basis.allSatisfy({ $0.count == dimension }) else { throw InputError.invalidShape }
        guard counts.allSatisfy({ $0.isFinite && $0 >= 2 }) else {
            throw InputError.unsupportedCount
        }
        guard descendingEigenvalues.allSatisfy(\.isFinite),
              basis.flatMap({ $0 }).allSatisfy(\.isFinite),
              zip(descendingEigenvalues, descendingEigenvalues.dropFirst()).allSatisfy({ $0 >= $1 }) else {
            throw InputError.invalidSpectrum
        }
        let scratch = counts.map { min($0 - 1, Double(dimension)) }
        let clipped = counts.allSatisfy { $0 <= Double(dimension) }
        // 48860 loads scratch[0]; 48868 subtracts another one; 4886c
        // truncates to unsigned; 4887c builds an inclusive subview endpoint.
        let retained = clipped ? Int((scratch[0] - 1).rounded(.towardZero)) + 1 : dimension
        guard retained > 0, retained <= dimension else { throw InputError.invalidShape }
        return Result(eigenvalues: Array(descendingEigenvalues.prefix(retained)),
                      basis: basis.map { Array($0.prefix(retained)) },
                      scratchCounts: scratch, wasClipped: clipped)
    }
}
