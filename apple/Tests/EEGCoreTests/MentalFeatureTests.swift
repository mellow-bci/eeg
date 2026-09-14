import Foundation
import XCTest
@testable import EEGCore

final class MentalFeatureTests: XCTestCase {
    private struct Source: Decodable { let samples: [EEGSample] }
    private struct Reference: Decodable {
        let values: [Double]; let names: [String]; let artifact_flags: [String]
        let feature_config_id: String; let usable: Bool
    }
    private func data(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("Fixtures/spectrum/\(name).json"))
    }
    func testAllSeventyRealRecordingFeaturesMatchIndependentPythonReference() throws {
        let source = try JSONDecoder().decode(Source.self, from: data("real"))
        let reference = try JSONDecoder().decode(Reference.self, from: data("real-features"))
        let result = try EEGMentalFeatures.extract(samples: source.samples)
        XCTAssertEqual(result.values.count, 70)
        XCTAssertEqual(EEGMentalFeatures.names, reference.names)
        XCTAssertEqual(EEGMentalFeatures.configurationID, reference.feature_config_id)
        XCTAssertEqual(result.artifactFlags, reference.artifact_flags)
        XCTAssertEqual(result.usable, reference.usable)
        for (actual, expected) in zip(result.values, reference.values) {
            XCTAssertEqual(actual, expected, accuracy: 1e-7)
        }
    }
    func testMissingAnyElectrodeRejectsWholeFeatureVector() throws {
        let source = try JSONDecoder().decode(Source.self, from: data("real"))
        for channel in EEGMentalFeatures.channelOrder {
            var samples = source.samples
            let s = samples[40]; var voltage = s.electrodesMicrovolts!
            voltage.removeValue(forKey: channel)
            samples[40] = EEGSample(index: s.index, counter: s.counter, receivedAt: s.receivedAt,
                continuous: s.continuous, adcWords: s.adcWords, electrodesADC: s.electrodesADC,
                electrodesMicrovolts: voltage, notificationSlot: s.notificationSlot, recordFlag: s.recordFlag)
            XCTAssertThrowsError(try EEGMentalFeatures.extract(samples: samples), channel)
        }
    }
}
