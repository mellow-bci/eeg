import Foundation
import XCTest
@testable import EEGCore

final class ReferenceMentalPipelineTests: XCTestCase {
    private func artificialRecipe() -> ReferenceMentalPipeline.Recipe {
        let identity = ReferenceGaussianPipeline.CenteredTransform(mean: [0], basis: [[1]])
        return .init(sampleRate: 32, samplesPerSeries: 32, seriesCount: 1,
                     bands: [.init(lowerHz: 3, upperHz: 3)], features: [.init(series: 0, band: 0)],
                     classifier: .init(pca: identity, canonical: identity, canonicalClassCount: 2,
                                       classes: [
                                        .init(components: [.init(weight: 1, mean: [0], covariance: [[0.001]])]),
                                        .init(components: [.init(weight: 1, mean: [0.5], covariance: [[0.001]])])
                                       ], classPriors: [0.5, 0.5], neutralScale: 0.01),
                     actions: [2], activationSetting: 7)
    }

    // These tests validate our comparison harness, not Cortex or mental intent.
    func testRejectedWindowDoesNotConsumeStateAndResetIsDeterministic() throws {
        let recipe = artificialRecipe()
        var pipeline = try ReferenceMentalPipeline(recipe: recipe)
        let tone = [(0..<32).map { cos(2 * Double.pi * 3 * Double($0) / 32) }]
        let first = try pipeline.process(preprocessedSeries: tone)
        XCTAssertEqual(first.features[0], 10 * log10(first.bandPowers[0][0]), accuracy: 1e-12)
        XCTAssertThrowsError(try pipeline.process(preprocessedSeries: [[Double.nan]]))
        var fresh = try ReferenceMentalPipeline(recipe: recipe)
        _ = try fresh.process(preprocessedSeries: tone)
        let expected = try fresh.process(preprocessedSeries: [Array(repeating: 1, count: 32)])
        let actual = try pipeline.process(preprocessedSeries: [Array(repeating: 1, count: 32)])
        XCTAssertEqual(actual.filteredPosterior, expected.filteredPosterior)
        XCTAssertEqual(actual.command, expected.command)
        pipeline.reset()
        let repeated = try pipeline.process(preprocessedSeries: tone)
        XCTAssertEqual(first.filteredPosterior, repeated.filteredPosterior)
        XCTAssertEqual(first.command, repeated.command)
    }

    func testNormalizedRecipeRoundTrip() throws {
        let recipe = try JSONDecoder().decode(ReferenceMentalPipeline.Recipe.self,
                                             from: JSONEncoder().encode(artificialRecipe()))
        var pipeline = try ReferenceMentalPipeline(recipe: recipe)
        XCTAssertEqual(try pipeline.process(preprocessedSeries: [Array(repeating: 1, count: 32)]).command.action, 1)
        XCTAssertThrowsError(try pipeline.process(preprocessedSeries: [Array(repeating: 0, count: 32)]))
    }

    struct Fixture: Decodable {
        let version: Int
        let referenceBinarySHA256: String
        let referenceProfileSHA256: String
        let referenceOutputsSHA256: String
        let origin: String
        let absoluteTolerance: Double
        let relativeTolerance: Double
        let recipe: ReferenceMentalPipeline.Recipe
        let frames: [ExpectedFrame]
    }
    struct ExpectedFrame: Decodable {
        let resetBefore: Bool
        let preprocessedSeries: [[Double]]
        let spectra: [[Double]]
        let bandPowers: [[Double]]
        let features: [Double]
        let pcaFeatures: [Double]
        let canonicalFeatures: [Double]
        let classDensity: [Double]
        let classPeakDensity: [Double]
        let posterior: [Double]
        let filteredPosterior: [Double]
        let action: Int
        let power: Double
    }

    /// External reference values only: no vendor assets in source/fixtures.
    /// Declared origin/hash fields are not independently authenticated here;
    /// the capture protocol and original file hashes must also be reviewed.
    /// A skipped test is missing evidence, never a comparison pass.
    func testExternalCortexStageComparison() throws {
        guard let path = ProcessInfo.processInfo.environment["EEG_CORTEX_COMPARISON_FIXTURE"] else {
            throw XCTSkip("No external Cortex profile/output fixture: matched-profile parity remains unverified")
        }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        guard fixture.version == 1, fixture.origin == "cortex-observed-stage-outputs",
              fixture.referenceBinarySHA256 == "cdb5083641488056ceacfb8f2a0a0db724c8ce50585fd48aecbdcd1d179f936a",
              [fixture.referenceProfileSHA256, fixture.referenceOutputsSHA256].allSatisfy({
                  $0.count == 64 && $0.allSatisfy({ $0.isHexDigit })
              }), !fixture.frames.isEmpty,
              fixture.absoluteTolerance.isFinite, fixture.relativeTolerance.isFinite,
              (0...0.0001).contains(fixture.absoluteTolerance),
              (0...0.0001).contains(fixture.relativeTolerance) else {
            XCTFail("Missing/unsupported comparison provenance, data or bounded tolerances")
            return
        }
        var pipeline = try ReferenceMentalPipeline(recipe: fixture.recipe)
        for (frameIndex, expected) in fixture.frames.enumerated() {
            if expected.resetBefore { pipeline.reset() }
            let actual = try pipeline.process(preprocessedSeries: expected.preprocessedSeries)
            let pairs: [(String, [Double], [Double])] = [
                ("spectra", actual.spectra.flatMap { $0 }, expected.spectra.flatMap { $0 }),
                ("bands", actual.bandPowers.flatMap { $0 }, expected.bandPowers.flatMap { $0 }),
                ("features", actual.features, expected.features),
                ("pca", actual.classification.pcaFeatures, expected.pcaFeatures),
                ("canonical", actual.classification.canonicalFeatures, expected.canonicalFeatures),
                ("density", actual.classification.classDensity, expected.classDensity),
                ("peak", actual.classification.classPeakDensity, expected.classPeakDensity),
                ("posterior", actual.classification.posterior, expected.posterior),
                ("lowpass", actual.filteredPosterior, expected.filteredPosterior),
                ("power", [actual.command.power], [expected.power])
            ]
            XCTAssertEqual(actual.spectra.map(\.count), expected.spectra.map(\.count))
            XCTAssertEqual(actual.bandPowers.map(\.count), expected.bandPowers.map(\.count))
            for (stage, values, reference) in pairs {
                XCTAssertEqual(values.count, reference.count, "frame \(frameIndex) \(stage) shape")
                guard values.count == reference.count else { continue }
                for i in values.indices {
                    let tolerance = fixture.absoluteTolerance + fixture.relativeTolerance * abs(reference[i])
                    XCTAssertTrue(values[i].isFinite && reference[i].isFinite &&
                                  abs(values[i] - reference[i]) <= tolerance,
                                  "frame \(frameIndex) \(stage)[\(i)] differs")
                }
            }
            XCTAssertEqual(actual.command.action, expected.action, "frame \(frameIndex) action")
        }
    }
}
