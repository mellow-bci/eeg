import Foundation

/// Comparison-only arithmetic derived from combineGaussian and its expression helpers.
/// This is not a live training recipe or a recovered trained vendor model.
enum ReferenceGaussianPooling {
    struct Distribution: Equatable, Codable {
        var counts: [Double]
        var mean: [Double]
        var covariance: [[Double]]
        var updateTime: UInt32
    }

    enum PoolingError: Error, Equatable {
        case invalidShape
        case invalidMeasurement
        case noSharedSupportedFeatures
        case nonFiniteResult
    }

    /// nil denotes an empty GaussianData. Input means/counts are one row of features.
    /// The boolean is deliberately named for its traced effect, not an inferred lifecycle.
    static func combine(_ first: Distribution?, _ second: Distribution?,
                        useFirstUpdateTime: Bool) throws -> Distribution? {
        if let first { try validate(first) }
        if let second { try validate(second) }
        guard let first else { return second }
        guard let second else { return first }
        guard first.counts.count == second.counts.count else { throw PoolingError.invalidShape }

        // The binary copies the input with the larger minimum feature count first;
        // ties choose the first. Nonselected cells remain from that input.
        var result = first.counts.min()! >= second.counts.min()! ? first : second
        let selected = first.counts.indices.filter { first.counts[$0] > 1 && second.counts[$0] > 1 }
        // Empty indexed subview behavior is intentionally outside this bounded kernel.
        guard !selected.isEmpty else { throw PoolingError.noSharedSupportedFeatures }
        for feature in selected {
            let a = first.counts[feature], b = second.counts[feature]
            result.counts[feature] = a + b
            result.mean[feature] = (first.mean[feature] * a + second.mean[feature] * b) / (a + b)
        }
        for row in selected {
            for column in selected {
                let a = min(first.counts[row], first.counts[column])
                let b = min(second.counts[row], second.counts[column])
                // min of summed counts differs from sum of pairwise minima.
                let total = min(result.counts[row], result.counts[column])
                let numerator = first.covariance[row][column] * (a - 1)
                    + (first.mean[row] * first.mean[column]) * a
                    + second.covariance[row][column] * (b - 1)
                    + (second.mean[row] * second.mean[column]) * b
                    - (result.mean[row] * result.mean[column]) * total
                result.covariance[row][column] = numerator / (total - 1)
            }
        }
        // ARM add w8 wraps at 32 bits before logical shift; do not silently use a
        // 64-bit mean. The true branch takes the first input timestamp verbatim.
        result.updateTime = useFirstUpdateTime ? first.updateTime : (first.updateTime &+ second.updateTime) >> 1
        guard result.counts.allSatisfy(\.isFinite), result.mean.allSatisfy(\.isFinite),
              result.covariance.allSatisfy({ $0.allSatisfy(\.isFinite) }) else {
            throw PoolingError.nonFiniteResult
        }
        return result
    }

    private static func validate(_ value: Distribution) throws {
        let dimension = value.counts.count
        guard dimension > 0, value.mean.count == dimension,
              value.covariance.count == dimension,
              value.covariance.allSatisfy({ $0.count == dimension }) else {
            throw PoolingError.invalidShape
        }
        // Independent support policy: finite, nonnegative counts and finite statistics.
        // No positivity repair, regularization or invented count interpolation is applied.
        guard value.counts.allSatisfy({ $0.isFinite && $0 >= 0 }),
              value.mean.allSatisfy(\.isFinite),
              value.covariance.allSatisfy({ $0.allSatisfy(\.isFinite) }) else {
            throw PoolingError.invalidMeasurement
        }
    }
}
