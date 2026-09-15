import Foundation
import XCTest
@testable import EEGCore

final class MentalScoringTests: XCTestCase {
    private struct Case: Decodable { let values: [Double]; let scores: [Double]; let label: String; let outside: Bool }
    private struct Fixture: Decodable { let parameters: EEGMentalScoringParameters; let cases: [Case] }
    private func fixture() throws -> Fixture {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appendingPathComponent("Fixtures/spectrum/mental-scoring.json")))
    }
    func testNativeTransformsAndGaussianScoresMatchPython() throws {
        let f = try fixture()
        for c in f.cases {
            let actual = try EEGMentalScoring.score(values: c.values, parameters: f.parameters)
            XCTAssertEqual(actual.candidateLabel, c.label)
            XCTAssertEqual(actual.outsideTrainingDistribution, c.outside)
            for (a, e) in zip(actual.uncalibratedScores, c.scores) { XCTAssertEqual(a, e, accuracy: 1e-10) }
        }
    }
    func testUnderflowedDensitiesNormalizeButCannotPromoteOutliers() throws {
        // Independent analytic 1-D example: both ordinary Gaussian densities
        // round to zero, but their likelihood ratio remains representable.
        let parameters = EEGMentalScoringParameters(classes: ["neutral", "task"],
            center: Array(repeating: 0, count: 70), scale: Array(repeating: 1, count: 70),
            selected: [0], pca_mean: [0], components: [[1]], gaussians: [
                .init(label: "neutral", mean: [0], variance: [1], distance_limit: 4),
                .init(label: "task", mean: [1], variance: [1], distance_limit: 4)])
        var values = Array(repeating: 0.0, count: 70)
        values[0] = 50
        XCTAssertEqual(exp(-0.5 * 50 * 50) / sqrt(2 * Double.pi), 0)
        XCTAssertEqual(exp(-0.5 * 49 * 49) / sqrt(2 * Double.pi), 0)
        let score = try EEGMentalScoring.score(values: values, parameters: parameters)
        let ratio = exp(-49.5)
        XCTAssertEqual(score.uncalibratedScores[0] / score.uncalibratedScores[1], ratio, accuracy: ratio * 1e-12)
        XCTAssertTrue(score.uncalibratedScores.allSatisfy { $0.isFinite && $0 >= 0 })
        XCTAssertEqual(score.uncalibratedScores.reduce(0, +), 1, accuracy: 1e-15)
        XCTAssertEqual(score.candidateLabel, "task")
        XCTAssertTrue(score.outsideTrainingDistribution)
        var detector = try EEGExperimentalDetector(parameters: parameters, settings: ProcessingSettings(),
            participantID: "synthetic", profileID: "analytic-underflow-test")
        for index in 0..<4 {
            let proposal = detector.infer(EEGInferenceWindow(values: values,
                feature_config_id: EEGMentalFeatures.configurationID, artifact_flags: [], usable: true,
                participant_id: "synthetic", session_id: "s", continuity_id: "segment-1",
                window_id: String(index), start: Double(index * 2), end: Double(index * 2 + 2)))
            XCTAssertEqual(proposal.reason, "out_of_training_distribution")
            XCTAssertNil(proposal.experimentalCandidate)
            XCTAssertNil(proposal.evidenceStart)
            XCTAssertNil(proposal.command)
            XCTAssertFalse(proposal.systemControlEnabled)
        }
    }
    func testInvalidAndExtremeFeaturesReject() throws {
        let f = try fixture()
        for values in [[Double](), [Double](repeating: .nan, count: 70), [Double](repeating: 1e308, count: 70)] {
            XCTAssertThrowsError(try EEGMentalScoring.score(values: values, parameters: f.parameters))
        }
    }

    func testGaussianCoordinateScaleDoesNotChangeDistanceOrRelativeScore() throws {
        // Analytic one-dimensional kernels, not trained/qualified profiles.
        // Scaling coordinates and variances together must preserve distances
        // and relative scores even at finite Double variance extremes.
        for variance in [1.0, 1e308, 4 * Double.leastNonzeroMagnitude] {
            let unit = sqrt(variance)
            let parameters = EEGMentalScoringParameters(classes: ["neutral", "task"],
                center: Array(repeating: 0, count: 70), scale: Array(repeating: 1, count: 70),
                selected: [0], pca_mean: [0], components: [[unit]], gaussians: [
                    .init(label: "neutral", mean: [0], variance: [variance], distance_limit: 3),
                    .init(label: "task", mean: [unit], variance: [variance], distance_limit: 3)])
            var values = Array(repeating: 0.0, count: 70)
            values[0] = 3
            let score = try EEGMentalScoring.score(values: values, parameters: parameters)
            XCTAssertEqual(score.squaredDistances[0], 9, accuracy: 1e-12)
            XCTAssertEqual(score.squaredDistances[1], 4, accuracy: 1e-12)
            XCTAssertEqual(score.uncalibratedScores[0] / score.uncalibratedScores[1], exp(-2.5), accuracy: 1e-12)
            XCTAssertTrue(score.outsideTrainingDistribution)
            XCTAssertEqual(score.candidateLabel, "task")

            // At the common mean, density is inversely proportional to SD.
            // The narrower Gaussian must have twice the score, independent of
            // absolute variance; this separately checks the log determinant.
            let unequal = EEGMentalScoringParameters(classes: ["neutral", "task"],
                center: parameters.center, scale: parameters.scale,
                selected: [0], pca_mean: [0], components: [[unit]], gaussians: [
                    .init(label: "neutral", mean: [0], variance: [variance], distance_limit: 3),
                    .init(label: "task", mean: [0], variance: [variance / 4], distance_limit: 3)])
            values[0] = 0
            let density = try EEGMentalScoring.score(values: values, parameters: unequal)
            XCTAssertEqual(density.uncalibratedScores[0], 1.0 / 3, accuracy: 1e-12)
            XCTAssertEqual(density.uncalibratedScores[1], 2.0 / 3, accuracy: 1e-12)
        }
    }
}
