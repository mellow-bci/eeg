import XCTest
@testable import EEGCore

/// Analytic fixture: proves stage composition for stated statistics only.
/// Not a recovered epoch recipe or a Cortex-observed trained profile.
final class ReferenceTrainingCompositionTests: XCTestCase {
    func testExplicitTwoClassStatisticsThroughTrainingAndNeutralDecision() throws {
        typealias G = ReferenceGaussianPipeline
        // Twenty analytic epochs, balanced and orthogonal across features.
        // Their unbiased sample covariance is diag(1,4).
        let amplitude = sqrt(19.0 / 20)
        let first = (0..<20).map { $0 < 10 ? -amplitude : amplitude }
        let second = (0..<20).map { $0 % 10 < 5 ? -2 * amplitude : 2 * amplitude }
        let leftFit = try ReferenceTrainingStatistics.fit(featureRows: [first.map { $0 - 2 }, second],
            coordinates: [0, 1], maximumEpochs: 20)
        let rightFit = try ReferenceTrainingStatistics.fit(featureRows: [first.map { $0 + 2 }, second],
            coordinates: [0, 1], maximumEpochs: 20)
        let left = ReferenceGaussianPooling.Distribution(counts: leftFit.epochCounts, mean: leftFit.average,
            covariance: leftFit.covariance, updateTime: 10)
        let right = ReferenceGaussianPooling.Distribution(counts: rightFit.epochCounts, mean: rightFit.average,
            covariance: rightFit.covariance, updateTime: 20)
        let selected = try ReferenceFeatureSelection.select([left, right].map {
            .init(mean: $0.mean, variance: [$0.covariance[0][0], $0.covariance[1][1]], epochCounts: $0.counts)
        })
        XCTAssertEqual(selected.selectedCoordinates, [0, 1])
        let total = try XCTUnwrap(ReferenceGaussianPooling.combine(left, right, useFirstUpdateTime: false))
        XCTAssertEqual(total.mean[0], 0, accuracy: 1e-13)
        XCTAssertEqual(total.mean[1], 0, accuracy: 1e-13)
        XCTAssertEqual(total.covariance[0][0], 198.0 / 39, accuracy: 1e-13)
        let pca = try G.covarianceEigenbasis(total.covariance)
        let retained = try ReferenceCanonicalTraining.pcaSelectedIndices(descendingEigenvalues: pca.eigenvalues, classCount: 2)
        XCTAssertEqual(retained, [0])
        let pcaBasis = pca.basis.map { row in retained.map { row[$0] } }
        let projected = try [left, right].map {
            try G.projectDistribution(.init(weight: 1, mean: $0.mean, covariance: $0.covariance), basis: pcaBasis)
        }
        let projectedTotal = try G.projectDistribution(.init(weight: 1, mean: total.mean,
            covariance: total.covariance), basis: pcaBasis)
        let dimensions = retained.count
        var within = Array(repeating: Array(repeating: 0.0, count: dimensions), count: dimensions)
        var between = within
        for r in 0..<dimensions { for c in 0..<dimensions {
            within[r][c] = 19 * projected[0].covariance[r][c] + 19 * projected[1].covariance[r][c]
            between[r][c] = 39 * projectedTotal.covariance[r][c] - within[r][c]
        } }
        let canonical = try ReferenceCanonicalTraining.fit(within: within, between: between,
            residualDegreesOfFreedom: 38, directions: 1)
        XCTAssertEqual(canonical.eigenvalues[0], 160.0 / 38, accuracy: 1e-12)
        let classComponents = try projected.map { try G.projectDistribution($0, basis: canonical.basis) }
        XCTAssertEqual(classComponents[0].mean[0], -2, accuracy: 1e-12)
        XCTAssertEqual(classComponents[1].mean[0], 2, accuracy: 1e-12)
        XCTAssertEqual(classComponents[1].covariance[0][0], 1, accuracy: 1e-12)
        let parameters = G.Parameters(pca: .init(mean: total.mean, basis: pcaBasis),
            canonical: .init(mean: projectedTotal.mean, basis: canonical.basis), canonicalClassCount: 2,
            classes: classComponents.map { .init(components: [$0]) }, classPriors: [0.5, 0.5], neutralScale: 0.01)
        let result = try G.infer(featureVector: [2, 0], parameters: parameters)
        XCTAssertEqual(result.classDensity[0] / result.classDensity[1], exp(-8), accuracy: 1e-12)
        var decision = try ReferenceCommandScoring(actions: [2], activationSetting: 3)
        XCTAssertEqual(try decision.process(filteredProbabilities: result.posterior).action, 2)
        let neutral = try G.infer(featureVector: [-2, 0], parameters: parameters)
        XCTAssertEqual(try decision.process(filteredProbabilities: neutral.posterior).action, 1)
    }
}
