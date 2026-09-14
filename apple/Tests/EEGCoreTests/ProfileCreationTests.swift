import Foundation
import XCTest
@testable import EEGCore

final class ProfileCreationTests: XCTestCase {
    private func records() throws -> [EEGTrainingRecord] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("Fixtures/spectrum/mental-training.json"))) as! [String: Any]
        var rows = object["records"] as! [[String: Any]]
        for i in rows.indices { rows[i]["participant_id"] = "participant-नमस्ते-🧠" }
        return try JSONDecoder().decode([EEGTrainingRecord].self, from: JSONSerialization.data(withJSONObject: rows))
    }
    func testNativeProfileRoundtripAndOptionalInteropExport() throws {
        let rows = try records(), parent = String(repeating: "a", count: 64)
        let artifact = try EEGProfileCreation.train(rows, participantID: "participant-नमस्ते-🧠", parentProfileID: parent)
        XCTAssertEqual(artifact.profile.participantID, "participant-नमस्ते-🧠")
        XCTAssertEqual(try EEGMentalProfile.load(data: artifact.data).id, artifact.profile.id)
        let object = try JSONSerialization.jsonObject(with: artifact.data) as! [String: Any]
        XCTAssertEqual(object["parent_profile_id"] as? String, parent)
        XCTAssertEqual(object["system_control_enabled"] as? Bool, false)
        XCTAssertEqual(artifact.data, try EEGProfileCreation.train(rows, participantID: "participant-नमस्ते-🧠", parentProfileID: parent).data)
        if let path = ProcessInfo.processInfo.environment["EEG_NATIVE_PROFILE_TEST_EXPORT"] {
            try artifact.data.write(to: URL(fileURLWithPath: path))
        }
    }
    func testExclusivePrivateSaveAndParentValidation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let rows = try records()
        let artifact = try EEGProfileCreation.train(rows, participantID: "participant-नमस्ते-🧠")
        let path = directory.appendingPathComponent("profile.json")
        try EEGProfileCreation.save(artifact, to: path)
        XCTAssertEqual(try Data(contentsOf: path), artifact.data)
        let mode = try FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions] as! NSNumber
        XCTAssertEqual(mode.intValue & 0o777, 0o600)
        XCTAssertThrowsError(try EEGProfileCreation.save(artifact, to: path))
        XCTAssertEqual(try Data(contentsOf: path), artifact.data)
        XCTAssertThrowsError(try EEGProfileCreation.train(rows, participantID: "participant-नमस्ते-🧠", parentProfileID: "invalid"))
    }
    func testPythonScalarSpelling() throws {
        let data = try PythonCompatibleJSON.encode(["x": [1e-7, 1e-5, 1e-4, 1e15, 1e16, -0.0], "s": "🧠\n"] as [String: Any])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "{\"s\":\"\\ud83e\\udde0\\n\",\"x\":[1e-07,1e-05,0.0001,1000000000000000.0,1e+16,-0.0]}")
    }
}
