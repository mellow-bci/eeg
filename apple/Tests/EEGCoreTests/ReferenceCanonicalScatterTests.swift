import XCTest
@testable import EEGCore

final class ReferenceCanonicalScatterTests: XCTestCase {
    func testTwoClassAnalyticScatter() throws {
        let result = try ReferenceCanonicalScatter.construct(classes: [
            .init(counts: [10, 10], mean: [0, 0], covariance: [[1, 0], [0, 4]]),
            .init(counts: [10, 10], mean: [2, 0], covariance: [[1, 0], [0, 4]])
        ], pcaBasis: [[1, 0], [0, 1]], maximumClasses: 2)
        XCTAssertEqual(result.totalCount, 20)
        XCTAssertEqual(result.classCounts, [10, 10])
        XCTAssertEqual(result.pooled.mean, [1, 0])
        XCTAssertEqual(result.withinScatter, [[18, 0], [0, 72]])
        XCTAssertEqual(result.totalScatter[0][0], 38, accuracy: 1e-12)
        XCTAssertEqual(result.betweenScatter[0][0], 20, accuracy: 1e-12)
        XCTAssertEqual(result.betweenScatter[1][1], 0, accuracy: 1e-12)
        XCTAssertEqual(result.residualDegreesOfFreedom, 18)
    }
    func testProjectionBeforePoolingReducesEachClassCount() throws {
        let result = try ReferenceCanonicalScatter.construct(classes: [
            .init(counts: [6, 20], mean: [0, 0], covariance: [[1, 0], [0, 1]]),
            .init(counts: [12, 30], mean: [3, 0], covariance: [[2, 0], [0, 2]])
        ], pcaBasis: [[1, 0], [0, 1]], maximumClasses: 2)
        XCTAssertEqual(result.classCounts, [6, 12])
        XCTAssertEqual(result.pooled.counts, [18, 18])
        XCTAssertEqual(result.pooled.mean, [2, 0])
        XCTAssertEqual(result.withinScatter, [[27, 0], [0, 27]])
        XCTAssertEqual(result.betweenScatter[0][0], 36, accuracy: 1e-12)
        XCTAssertEqual(result.residualDegreesOfFreedom, 16)
    }
    func testProjectionIsUncenteredAndCanReduceDimension() throws {
        let result = try ReferenceCanonicalScatter.construct(classes: [
            .init(counts: [8, 9], mean: [2, 3], covariance: [[1, 0], [0, 1]]),
            .init(counts: [8, 9], mean: [4, 5], covariance: [[1, 0], [0, 1]])
        ], pcaBasis: [[2], [1]], maximumClasses: 2)
        XCTAssertEqual(result.projectedClasses[0].mean, [7])
        XCTAssertEqual(result.projectedClasses[0].covariance, [[5]])
        XCTAssertEqual(result.pooled.mean, [10])
        XCTAssertEqual(result.betweenScatter[0][0], 144, accuracy: 1e-12)
    }
    func testSingularClassesReachCanonicalRetryThroughScatterConstruction() throws {
        let scatter = try ReferenceCanonicalScatter.construct(classes: [
            .init(counts: [8], mean: [1], covariance: [[0]]),
            .init(counts: [8], mean: [3], covariance: [[0]])
        ], pcaBasis: [[2]], maximumClasses: 2)
        XCTAssertEqual(scatter.projectedClasses.map(\.mean), [[2], [6]])
        XCTAssertEqual(scatter.projectedClasses.map(\.covariance), [[[0]], [[0]]])
        XCTAssertEqual(scatter.withinScatter, [[0]])
        XCTAssertEqual(scatter.betweenScatter[0][0], 64, accuracy: 1e-12)
        let fitted = try ReferenceTrainingEdgeCases.boundedCanonical(
            within: scatter.withinScatter, between: scatter.betweenScatter,
            residualDegreesOfFreedom: scatter.residualDegreesOfFreedom,
            directions: 1, maximumDiagonalAdditions: 1)
        XCTAssertEqual(fitted.diagonalAdditions, 1)
        XCTAssertEqual(fitted.repairedWithin, [[1e-10]])
        XCTAssertEqual(fitted.fit.eigenvalues[0], 64e10, accuracy: 1e-3)
        // Repair applies only to the fitting scatter, not to class density.
        XCTAssertThrowsError(try ReferenceGaussianPipeline.gaussianDensity([2], component:
            .init(weight: 1, mean: scatter.projectedClasses[0].mean,
                  covariance: scatter.projectedClasses[0].covariance)))
    }
    func testInvalidInputsAreExplicitFailures() {
        let valid = ReferenceCanonicalScatter.ClassStatistics(counts: [8], mean: [0], covariance: [[1]])
        XCTAssertThrowsError(try ReferenceCanonicalScatter.construct(classes: [valid], pcaBasis: [[1]], maximumClasses: 2))
        XCTAssertThrowsError(try ReferenceCanonicalScatter.construct(classes: [valid, valid], pcaBasis: [[1]], maximumClasses: 1))
        let unsupported = ReferenceCanonicalScatter.ClassStatistics(counts: [5], mean: [0], covariance: [[1]])
        XCTAssertThrowsError(try ReferenceCanonicalScatter.construct(classes: [valid, unsupported], pcaBasis: [[1]], maximumClasses: 2))
        let indefinite = ReferenceCanonicalScatter.ClassStatistics(counts: [8], mean: [0], covariance: [[-1]])
        XCTAssertThrowsError(try ReferenceCanonicalScatter.construct(classes: [valid, indefinite], pcaBasis: [[1]], maximumClasses: 2))
    }
}
