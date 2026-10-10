import XCTest
@testable import EEGCore

/// Authored mathematical inputs, not participant EEG or observed Cortex results.
final class ReferenceRawMentalWorkflowTests: XCTestCase {
    private typealias Workflow = ReferenceRawMentalWorkflow
    private func recipe(background: Bool = false) -> Workflow.Recipe {
        .init(sampleRate: 16, selectedChannelCount: 3, windowSeconds: 1, stepSeconds: 0.5,
              maximumBufferedSamples: 128, maximumSamplesPerBlock: 128,
              bands: [.init(lowerHz: 1, upperHz: 4)],
              features: [.power(.init(row: 0, band: 0)),
                         .ratio(numerator: .init(row: 0, band: 0), denominator: .init(row: 1, band: 0))],
              backgroundEnabled: background, actions: [2], activationSetting: 3)
    }
    private func data(count: Int = 48) -> [[Double]] {
        (0..<3).map { row -> [Double] in
            let frequency = 0.71 + Double(row) * 0.13
            let amplitude = Double(row + 1)
            return (0..<count).map { n -> Double in
                let phase = Double(n)
                let primary = sin(phase * frequency) * amplitude
                let secondary = cos(phase * 0.29 + Double(row)) * 0.4
                return primary + secondary
            }
        }
    }
    private func fittedRuntime() throws -> ReferenceRuntimeProfile.Runtime {
        let classes: [ReferenceSignatureTraining.ClassAlgebra] = [Int32(1), 2].map { id in
            .init(classReferenceID: id, distributions: [.init(counts: [20, 20],
                mean: id == 1 ? [0, 0] : [2, 4], covariance: [[1, 0], [0, 1]], updateTime: 0)])
        }
        let signature = try ReferenceClassifierRebuild.fit(classes,
            featureChannelMetadata: [[0, 0], [0, 0]], maximumClasses: 4,
            maximumCanonicalDiagonalAdditions: 3)
        let profile = try ReferenceRuntimeProfile.classifier(signature,
            numOfValidFeatures: signature.pca.basis[0].count, useCount: 0)
        return try ReferenceRuntimeProfile.runtime(profile, classPriors: [1, 1], neutralScale: 1)
    }
    private func frames(partition: Int, runtime: ReferenceRuntimeProfile.Runtime?) throws -> [Workflow.Frame] {
        var workflow = try Workflow(recipe: recipe(), runtime: runtime)
        let rows = data()
        var result: [Workflow.Frame] = []
        for start in stride(from: 0, to: rows[0].count, by: partition) {
            let end = min(start + partition, rows[0].count)
            let first = try workflow.process(selectedChannelSamples: rows.map { Array($0[start..<end]) },
                                             overallContactQuality: 100)
            if first.status != .waiting { result.append(first) }
            // Explicit ticks maintain the same epoch schedule across transport
            // partitions. The workflow itself never drains a backlog silently.
            while true {
                let next = try workflow.process(selectedChannelSamples: [], overallContactQuality: 100)
                if next.status == .waiting { break }
                result.append(next)
            }
        }
        return result
    }

    func testBlockPartitionsPreserveStagesAndFittedProfileInference() throws {
        let runtime = try fittedRuntime()
        let expected = try frames(partition: 48, runtime: runtime)
        XCTAssertEqual(expected.count, 5)
        for partition in [1, 3, 8, 17] {
            let actual = try frames(partition: partition, runtime: runtime)
            XCTAssertEqual(actual.count, expected.count)
            for (actual, expected) in zip(actual, expected) {
                XCTAssertEqual(actual.status, .inferred)
                XCTAssertEqual(actual.filteredEpoch, expected.filteredEpoch)
                XCTAssertEqual(actual.preprocessedEpoch, expected.preprocessedEpoch)
                XCTAssertEqual(actual.spectra, expected.spectra)
                XCTAssertEqual(actual.features, expected.features)
                XCTAssertEqual(actual.filteredPosterior, expected.filteredPosterior)
                XCTAssertEqual(actual.command, expected.command)
            }
        }
        XCTAssertEqual(expected[0].selectedChannelSamples, data())
        XCTAssertNotNil(expected[0].classification)
    }

    func testQualityRejectionIsVisibleAndDoesNotUpdateBackground() throws {
        var workflow = try Workflow(recipe: recipe(background: true), runtime: try fittedRuntime())
        let rejected = try workflow.process(selectedChannelSamples: data(count: 16), overallContactQuality: 49)
        XCTAssertEqual(rejected.status, .qualityRejected)
        XCTAssertFalse(try XCTUnwrap(rejected.features).clean)
        XCTAssertNil(rejected.command)
        XCTAssertNil(rejected.classification)
        let accepted = try workflow.process(selectedChannelSamples: data(count: 8), overallContactQuality: 50)
        XCTAssertEqual(accepted.status, .inferred)
        // First CLEAN feature initializes its own background, so subtraction is zero.
        XCTAssertEqual(accepted.features?.processed, [0, 0])
    }

    func testGapDiscardsAllHistoriesAndInsufficientSamplesRemainUnusable() throws {
        var workflow = try Workflow(recipe: recipe(), runtime: nil)
        let partial = try workflow.process(selectedChannelSamples: data(count: 8), overallContactQuality: 100)
        XCTAssertEqual(partial.status, .waiting)
        XCTAssertNil(partial.command)
        workflow.resetForGap()
        XCTAssertEqual(workflow.bufferedSamples, 0)
        let after = try workflow.process(selectedChannelSamples: data(count: 16), overallContactQuality: 100)
        var fresh = try Workflow(recipe: recipe(), runtime: nil)
        let baseline = try fresh.process(selectedChannelSamples: data(count: 16), overallContactQuality: 100)
        XCTAssertEqual(after.segment, 1)
        XCTAssertEqual(after.status, .featuresOnly)
        XCTAssertEqual(after.filteredEpoch, baseline.filteredEpoch)
        XCTAssertEqual(after.features, baseline.features)
        XCTAssertNil(after.classification)
    }

    func testMalformedAndNumericallyInvalidWindowsRejectAtomically() throws {
        var workflow = try Workflow(recipe: recipe(), runtime: nil)
        XCTAssertThrowsError(try workflow.process(selectedChannelSamples: [[.nan], [1], [2]], overallContactQuality: 100))
        XCTAssertEqual(workflow.bufferedSamples, 0)
        // All equal rows become zero after median subtraction: log power invalid.
        XCTAssertThrowsError(try workflow.process(selectedChannelSamples: Array(repeating: Array(repeating: 0, count: 16), count: 3), overallContactQuality: 100))
        XCTAssertEqual(workflow.bufferedSamples, 0)
        var fresh = try Workflow(recipe: recipe(), runtime: nil)
        let result = try workflow.process(selectedChannelSamples: data(count: 16), overallContactQuality: 100)
        let baseline = try fresh.process(selectedChannelSamples: data(count: 16), overallContactQuality: 100)
        XCTAssertEqual(result.filteredEpoch, baseline.filteredEpoch)
        XCTAssertEqual(result.features, baseline.features)
        XCTAssertThrowsError(try workflow.process(selectedChannelSamples: [], overallContactQuality: .infinity))
    }
}
