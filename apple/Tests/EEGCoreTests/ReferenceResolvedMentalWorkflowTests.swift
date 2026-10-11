import XCTest
@testable import EEGCore

/// Authored numerical fixtures, not hardware or same-model Cortex qualification.
final class ReferenceResolvedMentalWorkflowTests: XCTestCase {
    typealias W = ReferenceResolvedMentalWorkflow
    private var settings: W.Settings {
        .init(sampleRate: 128, maximumBufferedSamples: 512, maximumSamplesPerBlock: 256,
              maximumFeatures: 100, backgroundEnabled: false, actions: [2], activationSetting: 3)
    }
    private func profile(mode: Int32 = 1) -> ReferenceRuntimeRecipe.ConvertedProfile {
        .init(version: "20180327", values: [
            "cognitiv-bands": .matrix(.init(rows: 1, columns: 4, elements: [4,7,8,12])),
            "cognitiv-isBandPower": .integer(mode),
            "cognitiv-winSizeInSec": .floating(0.5),
            "cognitiv-stepSizeInSec": .floating(0.125)])
    }
    private func input(_ count: Int) -> [[Double]] {
        var result: [[Double]] = []
        for row in 0..<3 {
            let frequency = 0.31 + Double(row) * 0.13
            let amplitude = Double(row + 1)
            let values: [Double] = (0..<count).map { n in sin(Double(n) * frequency) * amplitude }
            result.append(values)
        }
        return result
    }
    private func make(_ p: ReferenceRuntimeRecipe.ConvertedProfile? = nil) throws -> W {
        try W(profile: p ?? profile(), headsetTypeID: 9, inputChannels: [92,999,54],
              settings: settings, runtime: nil)
    }
    func testLoadedRecipeAndReorderedMontageUseSharedStages() throws {
        for mode in [Int32(1),2] {
            var composed = try make(profile(mode: mode))
            XCTAssertEqual(composed.resolved.inputIndices, [2,0])
            XCTAssertFalse(composed.resolved.usedDefaultProfile)
            XCTAssertEqual(composed.rawRecipe.windowSeconds, 0.5)
            XCTAssertEqual(composed.rawRecipe.features.count, mode == 1 ? 4 : 5)
            var manual = try ReferenceRawMentalWorkflow(recipe: composed.rawRecipe, runtime: nil)
            let full = input(96)
            let actual = try composed.process(inputSamples: full, overallContactQuality: 100)
            let expected = try manual.process(selectedChannelSamples: [full[2],full[0]], overallContactQuality: 100)
            XCTAssertEqual(actual.inputSamples, full)
            XCTAssertEqual(actual.raw.selectedChannelSamples, [full[2],full[0]])
            XCTAssertEqual(actual.raw.filteredEpoch, expected.filteredEpoch)
            XCTAssertEqual(actual.raw.spectra, expected.spectra)
            XCTAssertEqual(actual.raw.features, expected.features)
            XCTAssertEqual(actual.raw.status, .featuresOnly)
            let backlog = try composed.process(inputSamples: [], overallContactQuality: 100)
            let manualBacklog = try manual.process(selectedChannelSamples: [], overallContactQuality: 100)
            XCTAssertEqual(backlog.raw.features, manualBacklog.features)
        }
    }
    func testVersionFallbackDoesNotMergeLoadedOverrides() throws {
        var old = profile(); old.version = "old"
        var composed = try make(old)
        XCTAssertTrue(composed.resolved.usedDefaultProfile)
        XCTAssertEqual(composed.rawRecipe.windowSeconds, 1)
        XCTAssertEqual(composed.rawRecipe.bands.count, 7)
        XCTAssertEqual(try composed.process(inputSamples: input(64), overallContactQuality: 100).raw.status, .waiting)
        var missing = profile(); missing.values.removeValue(forKey: "cognitiv-stepSizeInSec")
        XCTAssertThrowsError(try make(missing))
    }
    func testMalformedFullMatrixAndMissingChannelsRejectWithoutConsumingState() throws {
        XCTAssertThrowsError(try W(profile: profile(), headsetTypeID: 9, inputChannels: [92], settings: settings, runtime: nil))
        XCTAssertThrowsError(try W(profile: profile(), headsetTypeID: 9, inputChannels: [], settings: settings, runtime: nil))
        var composed = try make()
        XCTAssertThrowsError(try composed.process(inputSamples: [[1],[2]], overallContactQuality: 100))
        XCTAssertThrowsError(try composed.process(inputSamples: [[1],[2,3],[4]], overallContactQuality: 100))
        // Unselected rows must still be valid original measurements.
        XCTAssertThrowsError(try composed.process(inputSamples: [[1],[.nan],[2]], overallContactQuality: 100))
        XCTAssertThrowsError(try composed.process(inputSamples: input(257), overallContactQuality: 100))
        XCTAssertEqual(composed.bufferedSamples, 0)
        var fresh = try make()
        let a = try composed.process(inputSamples: input(64), overallContactQuality: 100)
        let b = try fresh.process(inputSamples: input(64), overallContactQuality: 100)
        XCTAssertEqual(a.raw.features, b.raw.features)
    }
    func testExplicitQualityGateManagerControlAndGapRemainShared() throws {
        var composed = try make()
        let idle = ReferenceManagerCadence.Control(classifierEmpty: true, autoSamplingNeutral: false, trainingControl: 0)
        XCTAssertEqual(try composed.process(inputSamples: input(64), overallContactQuality: 100,
            managerControl: idle).raw.status, .consumedWithoutFeatures)
        XCTAssertEqual(try composed.process(inputSamples: input(16), overallContactQuality: 49).raw.status, .qualityRejected)
        composed.resetForGap()
        XCTAssertEqual(composed.bufferedSamples, 0)
        let result = try composed.process(inputSamples: input(64), overallContactQuality: 100)
        XCTAssertEqual(result.raw.segment, 1)
        XCTAssertEqual(result.raw.status, .featuresOnly)
        XCTAssertNil(result.raw.command)
    }
}
