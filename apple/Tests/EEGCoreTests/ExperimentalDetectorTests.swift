import Foundation
import XCTest
@testable import EEGCore

final class ExperimentalDetectorTests: XCTestCase {
    private struct Fixture: Decodable { let parameters: EEGMentalScoringParameters }
    private func detector() throws -> EEGExperimentalDetector {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let f = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appendingPathComponent("Fixtures/spectrum/mental-scoring.json")))
        return try EEGExperimentalDetector(parameters: f.parameters, settings: ProcessingSettings(), participantID: "participant", profileID: "synthetic-test-only")
    }
    private func window(_ value: Double, _ start: Double, overrides: [String: Any] = [:]) throws -> EEGInferenceWindow {
        var fields: [String: Any] = ["values": [Double](repeating: value, count: 70),
            "feature_config_id": EEGMentalFeatures.configurationID, "artifact_flags": [String](), "usable": true,
            "participant_id": "participant", "session_id": "evaluation", "continuity_id": "segment-1",
            "window_id": "window-\(start)", "start": start, "end": start + 2]
        fields.merge(overrides) { _, new in new }
        return try JSONDecoder().decode(EEGInferenceWindow.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    func testPersistentTaskRemainsExperimentalAndNeverEnablesAction() throws {
        var d = try detector()
        XCTAssertEqual(d.infer(try window(4, 0)).reason, "insufficient_persistence")
        let output = d.infer(try window(4, 2))
        XCTAssertEqual(output.experimentalCandidate, "task")
        XCTAssertEqual(output.evidenceStart, 0)
        XCTAssertEqual(output.reason, "profile_not_hardware_validated")
        XCTAssertNil(output.command)
        XCTAssertFalse(output.systemControlEnabled)
        XCTAssertEqual(output.status, "no_reliable_command")
    }
    func testGapSessionAndContinuityChangesRestartPersistence() throws {
        for overrides: [String: Any] in [["start": 10, "end": 12], ["session_id": "other"], ["continuity_id": "segment-2"]] {
            var d = try detector(); _ = d.infer(try window(4, 0))
            XCTAssertEqual(d.infer(try window(4, 2, overrides: overrides)).reason, "insufficient_persistence")
        }
    }
    func testInvalidWindowsResetAndReturnExplicitReasons() throws {
        let cases: [([String: Any], String)] = [
            (["feature_config_id": "unknown"], "feature_configuration_mismatch"),
            (["artifact_flags": ["flat_channel"]], "invalid_or_artifact_window"),
            (["participant_id": "other"], "participant_mismatch"),
            (["window_id": ""], "missing_recording_identity"),
            (["continuity_id": ""], "missing_continuity_identity"),
            (["end": 2], "invalid_timing"),
            (["start": -1], "invalid_timing"),
            (["values": [Double]()], "invalid_features")]
        for (fields, reason) in cases {
            var d = try detector(); _ = d.infer(try window(4, 0))
            let output = d.infer(try window(4, 2, overrides: fields))
            XCTAssertEqual(output.reason, reason)
            XCTAssertNil(output.experimentalCandidate)
            XCTAssertEqual(d.infer(try window(4, 4)).reason, "insufficient_persistence")
        }
    }
    func testOverlappingAndReorderedWindowsCannotAccumulatePersistence() throws {
        for start in [1.99, 1.0, 0.0] {
            var d = try detector()
            _ = d.infer(try window(4, 0))
            let rejected = d.infer(try window(4, start))
            XCTAssertEqual(rejected.reason, "overlapping_or_reordered_window")
            XCTAssertNil(rejected.experimentalCandidate)
            XCTAssertNil(rejected.evidenceStart)
            XCTAssertNil(rejected.command)
            XCTAssertEqual(d.infer(try window(4, 4)).reason, "insufficient_persistence")
        }
        var adjacent = try detector()
        _ = adjacent.infer(try window(4, 0))
        XCTAssertEqual(adjacent.infer(try window(4, 2.0078125)).experimentalCandidate, "task")
    }
    func testNeutralOutliersAndNumericalFailureReset() throws {
        for (value, reason) in [(0.0, "neutral"), (10000.0, "out_of_training_distribution"), (1e308, "numerical_failure")] {
            var d = try detector(); _ = d.infer(try window(4, 0))
            let output = d.infer(try window(value, 2))
            XCTAssertEqual(output.reason, reason)
            XCTAssertNil(output.experimentalCandidate)
            XCTAssertEqual(d.infer(try window(4, 4)).reason, "insufficient_persistence")
        }
    }
}
