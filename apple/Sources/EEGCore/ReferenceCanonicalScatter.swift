import Foundation

/// Comparison-only runCanonicalDecomposition → manova1Cov arithmetic.
/// Inputs contain one Gaussian per class; no epoch/window/training policy is inferred.
enum ReferenceCanonicalScatter {
    struct ClassStatistics {
        let counts: [Double]
        let mean: [Double]
        let covariance: [[Double]]
    }
    struct Construction {
        let projectedClasses: [ClassStatistics]
        let pooled: ClassStatistics
        let classCounts: [Double]
        let totalCount: Double
        let totalScatter: [[Double]]
        let withinScatter: [[Double]]
        let betweenScatter: [[Double]]
        let residualDegreesOfFreedom: Double
        // pooled.mean is a measured pooled average, not a proven runtime center.
    }
    enum ConstructionError: Error { case invalidShape, capacityExceeded, nonFiniteResult }

    static func construct(classes: [ClassStatistics], pcaBasis: [[Double]],
                          maximumClasses: Int) throws -> Construction {
        // 70-dimensional finite/PSD support is our comparison boundary, not vendor policy.
        guard maximumClasses >= 2, classes.count <= maximumClasses else {
            throw ConstructionError.capacityExceeded
        }
        guard classes.count >= 2, let first = classes.first,
              (1...70).contains(first.mean.count), pcaBasis.count == first.mean.count,
              let dimension = pcaBasis.first?.count, (1...70).contains(dimension),
              pcaBasis.allSatisfy({ $0.count == dimension }) else {
            throw ConstructionError.invalidShape
        }
        var projected: [ClassStatistics] = []
        var pooled: ReferenceGaussianPooling.Distribution?
        for value in classes {
            guard value.mean.count == first.mean.count, value.counts.count == value.mean.count else {
                throw ConstructionError.invalidShape
            }
            let component = try ReferenceGaussianProjection.project(
                .init(weight: 1, mean: value.mean, covariance: value.covariance), basis: pcaBasis)
            let counts = try ReferenceEpochCounts.projectedCounts([value.counts], outputDimension: dimension)
            let item = ClassStatistics(counts: counts, mean: component.mean, covariance: component.covariance)
            projected.append(item)
            // Timestamp is deliberately absent from this arithmetic contract. Zero is
            // an internal placeholder and is never exposed as a measured timestamp.
            pooled = try ReferenceGaussianPooling.combine(pooled,
                .init(counts: counts, mean: item.mean, covariance: item.covariance, updateTime: 0),
                useFirstUpdateTime: false)
        }
        guard let pooled else { throw ConstructionError.invalidShape }
        let totalCount = try ReferenceEpochCounts.projectedCounts([pooled.counts], outputDimension: 1)[0]
        let classCounts = try projected.map {
            try ReferenceEpochCounts.projectedCounts([$0.counts], outputDimension: 1)[0]
        }
        var total = Array(repeating: Array(repeating: 0.0, count: dimension), count: dimension)
        var within = total
        var between = total
        for row in 0..<dimension {
            for column in 0..<dimension {
                total[row][column] = (totalCount - 1) * pooled.covariance[row][column]
                for index in projected.indices {
                    within[row][column] += (classCounts[index] - 1) * projected[index].covariance[row][column]
                }
                between[row][column] = total[row][column] - within[row][column]
            }
        }
        let df = totalCount - Double(classes.count)
        guard df.isFinite, total.allSatisfy({ $0.allSatisfy(\.isFinite) }),
              within.allSatisfy({ $0.allSatisfy(\.isFinite) }),
              between.allSatisfy({ $0.allSatisfy(\.isFinite) }) else {
            throw ConstructionError.nonFiniteResult
        }
        return .init(projectedClasses: projected,
                     pooled: .init(counts: pooled.counts, mean: pooled.mean, covariance: pooled.covariance),
                     classCounts: classCounts, totalCount: totalCount, totalScatter: total,
                     withinScatter: within, betweenScatter: between, residualDegreesOfFreedom: df)
    }
}
