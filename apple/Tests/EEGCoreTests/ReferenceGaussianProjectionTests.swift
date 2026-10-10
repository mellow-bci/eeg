import XCTest
@testable import EEGCore

final class ReferenceGaussianProjectionTests: XCTestCase {
    func testSingularInputKeepsExactZeroDirectionsWithoutRepair() throws {
        let result = try ReferenceGaussianProjection.project(
            .init(weight: 1, mean: [2, 3], covariance: [[4, 0], [0, 0]]), basis: [[1, 0], [0, 1]])
        XCTAssertEqual(result.mean, [2, 3])
        XCTAssertEqual(result.covariance, [[4, 0], [0, 0]])
        XCTAssertThrowsError(try ReferenceGaussianPipeline.gaussianDensity(result.mean, component: result))
    }
    func testSingularInputCanProjectIntoPositiveVarianceSubspace() throws {
        let result = try ReferenceGaussianProjection.project(
            .init(weight: 1, mean: [2, 3], covariance: [[4, 0], [0, 0]]), basis: [[2], [1]])
        XCTAssertEqual(result.mean, [7])
        XCTAssertEqual(result.covariance, [[16]])
        let density = try ReferenceGaussianPipeline.gaussianDensity([7], component: result)
        XCTAssertEqual(density.value, 1 / sqrt(32 * Double.pi), accuracy: 1e-12)
    }
    func testZeroProjectedWithinScatterCanReachExplicitCanonicalRetry() throws {
        let first = try ReferenceGaussianProjection.project(
            .init(weight: 1, mean: [1], covariance: [[0]]), basis: [[2]])
        let second = try ReferenceGaussianProjection.project(
            .init(weight: 1, mean: [3], covariance: [[0]]), basis: [[2]])
        let pooled = try XCTUnwrap(ReferenceGaussianPooling.combine(
            .init(counts: [8], mean: first.mean, covariance: first.covariance, updateTime: 0),
            .init(counts: [8], mean: second.mean, covariance: second.covariance, updateTime: 0),
            useFirstUpdateTime: false))
        let within = 7 * first.covariance[0][0] + 7 * second.covariance[0][0]
        let between = 15 * pooled.covariance[0][0] - within
        XCTAssertEqual(within, 0)
        XCTAssertEqual(between, 64, accuracy: 1e-12)
        let fit = try ReferenceTrainingEdgeCases.boundedCanonical(within: [[within]], between: [[between]],
            residualDegreesOfFreedom: 14, directions: 1, maximumDiagonalAdditions: 1)
        XCTAssertEqual(fit.diagonalAdditions, 1)
        XCTAssertEqual(fit.repairedWithin, [[1e-10]])
        XCTAssertEqual(fit.fit.eigenvalues[0], 64e10, accuracy: 1e-3)
        // Canonical diagonal repair must not mutate measured class covariances.
        XCTAssertEqual(first.covariance, [[0]])
        XCTAssertEqual(second.covariance, [[0]])
    }
    func testStrictAndPSDProjectionAgreeOnPositiveDefiniteInput() throws {
        let input = ReferenceGaussianPipeline.Component(weight: 0.5, mean: [2, 5], covariance: [[4, 1], [1, 2]])
        let strict = try ReferenceGaussianPipeline.projectDistribution(input, basis: [[1], [2]])
        let projected = try ReferenceGaussianProjection.project(input, basis: [[1], [2]])
        XCTAssertEqual(projected.mean, strict.mean)
        XCTAssertEqual(projected.covariance, strict.covariance)
        XCTAssertEqual(projected.weight, strict.weight)
    }
    func testIndefiniteAndMalformedInputsFail() {
        XCTAssertThrowsError(try ReferenceGaussianProjection.project(
            .init(weight: 1, mean: [0], covariance: [[-1]]), basis: [[1]]))
        XCTAssertThrowsError(try ReferenceGaussianProjection.project(
            .init(weight: 1, mean: [0], covariance: [[0]]), basis: [[]]))
        XCTAssertThrowsError(try ReferenceGaussianProjection.project(
            .init(weight: 1, mean: [0], covariance: [[0]]), basis: [[Double.infinity]]))
    }
}
