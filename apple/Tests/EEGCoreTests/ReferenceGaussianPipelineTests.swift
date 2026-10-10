import XCTest
@testable import EEGCore

final class ReferenceGaussianPipelineTests: XCTestCase {
    private typealias Pipeline = ReferenceGaussianPipeline

    func testCenteredTransformOrientationAndCanonicalTruncation() throws {
        let transform = Pipeline.CenteredTransform(mean: [1, 2], basis: [[1, 2, 3], [-1, 1, 0]])
        XCTAssertEqual(try Pipeline.transform([5, 9], using: transform), [-3, 15, 12])
        XCTAssertEqual(try Pipeline.canonicalTransform([5, 9], using: transform, classCount: 3), [-3, 15])
        XCTAssertEqual(try Pipeline.canonicalTransform([5, 9], using: transform, classCount: 1), [-3, 15, 12])
        XCTAssertThrowsError(try Pipeline.canonicalTransform([5, 9], using: transform, classCount: 5))
        XCTAssertThrowsError(try Pipeline.canonicalTransform([5, 9], using: transform, classCount: 0))
        XCTAssertThrowsError(try Pipeline.transform([5, .nan], using: transform))
        XCTAssertThrowsError(try Pipeline.transform([5], using: transform))
    }

    func testCorrelatedGaussianMatchesClosedForm() throws {
        // det(Sigma)=8, inverse=1/8 * [[3,-2],[-2,4]]. For delta=[2,1],
        // Mahalanobis distance=1. This detects a diagonal-covariance shortcut.
        let component = Pipeline.Component(weight: 1, mean: [1, -1], covariance: [[4, 2], [2, 3]])
        let result = try Pipeline.gaussianDensity([3, 0], component: component)
        let peak = 1 / (2 * Double.pi * sqrt(8))
        XCTAssertEqual(result.atMean, peak, accuracy: 1e-14)
        XCTAssertEqual(result.value, peak * exp(-0.5), accuracy: 1e-14)
        XCTAssertEqual(result.logValue, log(peak) - 0.5, accuracy: 1e-14)
        XCTAssertEqual(try Pipeline.gaussianDensity([1, -1], component: component).value, peak, accuracy: 1e-14)
    }

    func testThreeDimensionalGaussianAgainstAdjugateDeterminantOracle() throws {
        // Independently calculated with the 3x3 adjugate inverse, not Cholesky.
        // det=8.362 and delta^T inverse(Sigma) delta=7.063651040420952.
        let component = Pipeline.Component(weight: 1, mean: [0.2, 0.5, -0.7],
            covariance: [[2, 0.3, -0.4], [0.3, 1.5, 0.2], [-0.4, 0.2, 3]])
        let result = try Pipeline.gaussianDensity([0.75, -1.25, 2.5], component: component)
        XCTAssertEqual(result.atMean, 0.021957106878454844, accuracy: 1e-14)
        XCTAssertEqual(result.value, 0.0006422776081480233, accuracy: 1e-15)
        XCTAssertEqual(result.logValue, -7.35048993629168, accuracy: 1e-13)
    }

    func testMixturePreservesWeightsAndUsesEachComponentsOwnPeak() throws {
        let mixture = Pipeline.Mixture(components: [
            .init(weight: 2, mean: [0], covariance: [[1]]),
            .init(weight: 3, mean: [2], covariance: [[4]])
        ])
        let result = try Pipeline.mixtureDensity([0], mixture: mixture)
        let normalPeak = 1 / sqrt(2 * Double.pi)
        XCTAssertEqual(result.value, 2 * normalPeak + 1.5 * normalPeak * exp(-0.5), accuracy: 1e-14)
        XCTAssertEqual(result.atMean, 3.5 * normalPeak, accuracy: 1e-14)
        // Peak is a sum of component self-peaks, not the mixture at a single mean.
        XCTAssertGreaterThan(result.atMean, result.value)
    }

    func testPosteriorMultipliesPriorsOnlyIntoClassSlots() throws {
        let result = try Pipeline.posterior(density: [2, 3], peakDensity: [8, 4],
                                           priors: [0.25, 0.5], neutralScale: 0.5)
        XCTAssertEqual(result, [0.125, 0.375, 0.5])
        XCTAssertEqual(try Pipeline.posterior(density: [0, 0], peakDensity: [8, 4],
                                             priors: [0.25, 0.5], neutralScale: 0.5), [0, 0, 1])
        XCTAssertEqual(try Pipeline.posterior(density: [2, 3], peakDensity: [8, 4],
                                             priors: [0.25, 0.5], neutralScale: 0), [0.25, 0.75, 0])
        XCTAssertThrowsError(try Pipeline.posterior(density: [0], peakDensity: [1], priors: [1], neutralScale: 0))
        XCTAssertThrowsError(try Pipeline.posterior(density: [1], peakDensity: [1], priors: [-1], neutralScale: 1))
        XCTAssertThrowsError(try Pipeline.posterior(density: [1], peakDensity: [1], priors: [1], neutralScale: .nan))
    }

    func testExplicitFeatureToPosteriorWorkflow() throws {
        let parameters = Pipeline.Parameters(
            pca: .init(mean: [1, 2], basis: [[2, 0], [0, 1]]),
            canonical: .init(mean: [1, 1], basis: [[1, 9], [2, 8]]),
            canonicalClassCount: 2,
            classes: [.init(components: [.init(weight: 1, mean: [3], covariance: [[4]])]),
                      .init(components: [.init(weight: 1, mean: [1], covariance: [[4]])])],
            classPriors: [0.5, 0.5], neutralScale: 0.25)
        let result = try Pipeline.infer(featureVector: [2, 4], parameters: parameters)
        XCTAssertEqual(result.pcaFeatures, [2, 2])
        XCTAssertEqual(result.canonicalFeatures, [3])
        let e = exp(-0.5)
        let denominator = 0.5 + 0.5 * e + 0.25
        let expected = [0.5 / denominator, 0.5 * e / denominator, 0.25 / denominator]
        for (actual, expected) in zip(result.posterior, expected) {
            XCTAssertEqual(actual, expected, accuracy: 1e-14)
        }
        XCTAssertEqual(result.posterior.reduce(0, +), 1, accuracy: 1e-14)
    }

    func testUnsupportedCovariancesFailWithoutSilentRepair() {
        for covariance in [[[1.0, 1], [1, 1]], [[1, 2], [2, 1]], [[1, 0], [0.1, 1]], [[1, 0], [0, .nan]]] {
            XCTAssertThrowsError(try Pipeline.gaussianDensity([0, 0], component:
                .init(weight: 1, mean: [0, 0], covariance: covariance)))
        }
        XCTAssertThrowsError(try Pipeline.gaussianDensity([0], component:
            .init(weight: 1, mean: [0], covariance: [[0]])))
        XCTAssertThrowsError(try Pipeline.mixtureDensity([0], mixture:
            .init(components: [.init(weight: -1, mean: [0], covariance: [[1]])])))
        XCTAssertThrowsError(try Pipeline.mixtureDensity([0], mixture:
            .init(components: [.init(weight: 0, mean: [0], covariance: [[1]])])))
    }
}
