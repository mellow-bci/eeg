import Foundation

/// Comparison-only reconstruction of the MANOVA Bartlett diagnostic arithmetic.
/// This does not select a statistically significant rank: the captured function
/// validates alpha but does not preserve it or compute a significance decision.
enum ReferenceBartlettSelection {
    enum InputError: Error, Equatable {
        case invalidShape, invalidValue, arithmeticOverflow
    }

    struct Diagnostics: Sendable {
        let reverseReciprocalProducts: [Double]
        let statistics: [Double]
        let degreesOfFreedom: [Double]
        let multiplier: Double
    }

    /// Roots must be the full ascending eigenvalue vector before rank truncation.
    /// effectiveEpochCount is the caller's already derived N, not raw row count.
    /// Preserve multiplication then reciprocal then log, as in the binary;
    /// replacing this with sums of logarithms changes rounding/overflow behavior.
    static func diagnostics(ascendingRoots: [Double], classCount: Int,
                            effectiveEpochCount: Double) throws -> Diagnostics {
        let p = ascendingRoots.count
        guard p > 0, classCount >= 2 else { throw InputError.invalidShape }
        guard effectiveEpochCount.isFinite, effectiveEpochCount > 0,
              ascendingRoots.allSatisfy({ $0.isFinite && $0 > -1 }),
              zip(ascendingRoots, ascendingRoots.dropFirst()).allSatisfy({ $0 <= $1 })
        else { throw InputError.invalidValue }

        var product = 1.0
        var cumulative = [Double]()
        for root in ascendingRoots {
            product *= root + 1
            guard product.isFinite, product > 0 else { throw InputError.arithmeticOverflow }
            cumulative.append(product)
        }
        let r = min(p, classCount - 1)
        let lambda = cumulative.reversed().prefix(r).map { 1 / $0 }
        let multiplier = -(effectiveEpochCount - 1 - (Double(p) + Double(classCount)) * 0.5)
        let statistics = lambda.map { multiplier * log($0) }
        guard multiplier.isFinite, lambda.allSatisfy({ $0.isFinite && $0 > 0 }),
              statistics.allSatisfy(\.isFinite) else { throw InputError.arithmeticOverflow }
        return Diagnostics(reverseReciprocalProducts: lambda,
                           statistics: statistics,
                           degreesOfFreedom: (0..<r).map { Double(p - $0) * Double(classCount - 1 - $0) },
                           multiplier: multiplier)
    }
}
