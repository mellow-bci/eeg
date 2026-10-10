import XCTest
@testable import EEGCore

/// Synthetic stage-boundary checks, NOT a vendor recipe or physiological trial.
final class ReferencePipelineCompositionTests: XCTestCase {
    func testSpectralFeatureThroughTransformsGaussianAndNeutralScoring() throws {
        // Explicit artificial one-feature recipe. It deliberately does not guess
        // the vendor channel mapping, feature selection or trained parameters.
        let n = 32
        let tone = (0..<n).map { cos(2 * Double.pi * 3 * Double($0) / Double(n)) }
        let windowed = try ReferenceMentalKernels.window(tone)
        let spectrum = try ReferenceSpectralPipeline.spectrum(windowed)
        let features = try ReferenceSpectralPipeline.bands(spectrum, sampleRate: 32,
            bands: [.init(lowerHz: 3, upperHz: 3)])
        let commandMean = features[0]
        let identity = ReferenceGaussianPipeline.CenteredTransform(mean: [0], basis: [[1]])
        let params = ReferenceGaussianPipeline.Parameters(pca: identity, canonical: identity,
            canonicalClassCount: 2,
            classes: [
                .init(components: [.init(weight: 1, mean: [0], covariance: [[0.001]])]),
                .init(components: [.init(weight: 1, mean: [commandMean], covariance: [[0.001]])])
            ], classPriors: [0.5, 0.5], neutralScale: 0.01)
        let command = try ReferenceGaussianPipeline.infer(featureVector: features, parameters: params)
        var filters = Array(repeating: ReferenceScoringLowpass(), count: 3)
        var scorer = try ReferenceCommandScoring(actions: [2], activationSetting: 7)
        // Our explicit test cadence: one update per feature vector, per slot.
        func filtered(_ values: [Double]) throws -> [Double] {
            try values.indices.map { try filters[$0].process([values[$0]])[0] }
        }
        XCTAssertEqual(try scorer.process(filteredProbabilities: filtered(command.posterior)).action, 2)
        let neutral = try ReferenceGaussianPipeline.infer(featureVector: [0], parameters: params)
        for _ in 0..<40 { _ = try scorer.process(filteredProbabilities: filtered(neutral.posterior)) }
        XCTAssertEqual(try scorer.process(filteredProbabilities: filtered(neutral.posterior)).action, 1)
        XCTAssertFalse(scorer.isActivated)
        let unknown = try ReferenceGaussianPipeline.infer(featureVector: [10], parameters: params)
        XCTAssertEqual(unknown.posterior, [0, 0, 1])
        for i in filters.indices { filters[i].reset() }
        scorer.reset()
        XCTAssertEqual(try scorer.process(filteredProbabilities: filtered(unknown.posterior)).action, 1)
    }
}
