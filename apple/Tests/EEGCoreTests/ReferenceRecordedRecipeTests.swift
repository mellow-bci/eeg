import Foundation
import XCTest
@testable import EEGCore

/// Real archived decoded measurements. No reliable physiological labels or
/// classified contact mapping are inferred from this recording.
final class ReferenceRecordedRecipeTests: XCTestCase {
    func testArchivedVoltageReplayWithDefaultRecipeRemainsDiagnosticOnly() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("archive/current-state/epoc-paired-20260915-02.jsonl")
        guard FileManager.default.fileExists(atPath: file.path) else { throw XCTSkip("Private archived recording unavailable; git lfs pull required") }
        let bytes = try Data(contentsOf: file)
        guard !bytes.starts(with: Data("version https://git-lfs.github.com/spec".utf8)) else { throw XCTSkip("Private LFS recording not materialized") }
        let defaults = ReferenceDeployedRecipe.defaultProfile
        // Explicit archived montage; no numeric HeadsetType inference is made.
        let names = ReferenceChannelMetadata.defaultTrainingChannels.map(ReferenceChannelMetadata.databaseName)
        let features = try ReferenceDeployedRecipe.features(channelCount: names.count,
            bandCount: defaults.bands.count, isBandPower: defaults.isBandPower, maximumFeatures: 256)
        let recipe = ReferenceRawMentalWorkflow.Recipe(sampleRate: 128, selectedChannelCount: names.count,
            windowSeconds: defaults.windowSeconds, stepSeconds: defaults.stepSeconds,
            maximumBufferedSamples: 256, maximumSamplesPerBlock: 256, bands: defaults.bands,
            features: features, backgroundEnabled: false, actions: [2], activationSetting: 3)
        var first = try ReferenceRawMentalWorkflow(recipe: recipe, runtime: nil)
        var second = try ReferenceRawMentalWorkflow(recipe: recipe, runtime: nil)
        var sampleCount = 0, epochCount = 0
        for line in String(decoding: bytes, as: UTF8.self).split(separator: "\n") {
            let row = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            guard row["kind"] as? String == "eeg_adc" else { continue }
            if row["continuous"] as? Bool != true { first.resetForGap(); second.resetForGap() }
            let voltages = try XCTUnwrap(row["electrodes_microvolts"] as? [String: Double])
            let block = try names.map { [try XCTUnwrap(voltages[$0])] }
            // Unknown classified quality is deliberately rejected, never "100%".
            let a = try first.process(selectedChannelSamples: block, overallContactQuality: 0)
            let b = try second.process(selectedChannelSamples: block, overallContactQuality: 0)
            XCTAssertEqual(a.filteredEpoch, b.filteredEpoch)
            XCTAssertEqual(a.bandPowers, b.bandPowers)
            XCTAssertEqual(a.features, b.features)
            XCTAssertNil(a.command); XCTAssertNil(a.classification)
            if let extracted = a.features {
                epochCount += 1
                XCTAssertEqual(a.status, .qualityRejected)
                XCTAssertEqual(extracted.original.count, 98)
                XCTAssertTrue(extracted.original.allSatisfy(\.isFinite))
            }
            sampleCount += 1
        }
        XCTAssertEqual(sampleCount, 3858)
        XCTAssertGreaterThan(epochCount, 100)
    }
}
