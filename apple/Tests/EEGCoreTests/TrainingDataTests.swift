import Foundation
import XCTest
@testable import EEGCore

final class TrainingDataTests: XCTestCase {
    private struct Fixture: Decodable {
        struct Expected: Decodable { let classes: [String]; let center: [Double]; let scale: [Double]; let selected: [Int]; let pca_mean: [Double] }
        let records: [EEGTrainingRecord]
        let expected: Expected
        let centered_selected: [[Double]]
    }
    private func data() throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("Fixtures/spectrum/mental-training.json"))
    }
    func testNativePreparationMatchesPythonTrainer() throws {
        let fixture = try JSONDecoder().decode(Fixture.self, from: data())
        let result = try EEGTrainingData.prepare(fixture.records, participantID: "participant")
        XCTAssertEqual(result.classes, fixture.expected.classes)
        XCTAssertEqual(result.selected, fixture.expected.selected)
        for (actual, expected) in zip(result.center + result.scale + result.pcaMean + result.centeredSelected.flatMap { $0 },
                                      fixture.expected.center + fixture.expected.scale + fixture.expected.pca_mean + fixture.centered_selected.flatMap { $0 }) {
            XCTAssertEqual(actual, expected, accuracy: 1e-10)
        }
        XCTAssertEqual(result.centeredSelected.count, 80)
        XCTAssertEqual(result.recordingHashes.count, 2)
        XCTAssertEqual(result.windowIDs.count, 80)
    }
    func testRejectsUnverifiedArtifactAndProvenanceVariants() throws {
        let fixture = try JSONSerialization.jsonObject(with: data()) as! [String: Any]
        let original = fixture["records"] as! [[String: Any]]
        let variants: [(inout [[String: Any]]) -> Void] = [
            { $0[0]["label_verified"] = false },
            { $0[0]["accepted"] = false },
            { $0[0]["usable"] = false },
            { $0[0]["artifact_flags"] = ["blink"] },
            { $0[0]["participant_id"] = "other" },
            { $0[0]["feature_config_id"] = "unknown" },
            { $0[0]["values"] = [0] },
            { rows in rows[0]["window_id"] = rows[1]["window_id"] },
            { $0[0]["recording_content_sha256"] = "invalid" },
            { rows in for i in rows.indices { rows[i]["recording_content_sha256"] = String(repeating: "a", count: 64) } },
            { rows in rows.removeAll { $0["session_id"] as? String == "train-b" } },
            { rows in rows.removeAll { $0["label"] as? String == "neutral" } }
        ]
        for variant in variants {
            var rows = original; variant(&rows)
            let records = try JSONDecoder().decode([EEGTrainingRecord].self, from: JSONSerialization.data(withJSONObject: rows))
            XCTAssertThrowsError(try EEGTrainingData.prepare(records, participantID: "participant"))
        }
    }
    func testBudgetAndNumericalOverflowAreExplicitFailures() throws {
        let fixture = try JSONDecoder().decode(Fixture.self, from: data())
        var settings = ProcessingSettings(); settings.maxTrainingWindows = 79
        XCTAssertThrowsError(try EEGTrainingData.prepare(fixture.records, participantID: "participant", settings: settings))
        var object = try JSONSerialization.jsonObject(with: data()) as! [String: Any]
        var rows = object["records"] as! [[String: Any]]
        for i in rows.indices { rows[i]["values"] = [Double](repeating: Double.greatestFiniteMagnitude, count: 70) }
        object["records"] = rows
        let overflow = try JSONDecoder().decode(Fixture.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try EEGTrainingData.prepare(overflow.records, participantID: "participant"))
    }
}
