import Foundation
import XCTest
@testable import EEGCore

final class MentalProfileTests: XCTestCase {
    private func fixture() throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("Fixtures/spectrum/mental-profile.json"))
    }
    private func resigned(_ update: (inout [String: Any]) -> Void) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: fixture()) as! [String: Any]
        update(&object)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        object["profile_id"] = try ProfileCanonicalJSON.digest(data)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
    func testLoadsPythonProfileWithExactIntegrity() throws {
        let data = try fixture()
        let profile = try EEGMentalProfile.load(data: data)
        XCTAssertEqual(profile.participantID, "participant")
        XCTAssertEqual(profile.trainingSessions, ["train-a", "train-b"])
        XCTAssertEqual(profile.id, try ProfileCanonicalJSON.digest(data))
        _ = try profile.makeDetector()
        // Removing indentation doesn't change Python token spellings or checksum.
        let compact = String(decoding: data, as: UTF8.self).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined()
        XCTAssertEqual(try EEGMentalProfile.load(data: Data(compact.utf8)).id, profile.id)
    }
    func testTamperingAndDuplicateKeysRejected() throws {
        let text = String(decoding: try fixture(), as: UTF8.self)
        XCTAssertThrowsError(try EEGMentalProfile.load(data: Data(text.replacingOccurrences(of: "participant", with: "somebody-else").utf8)))
        let duplicate = text.replacingOccurrences(of: "{", with: "{\"schema\":\"eeg.mental-profile.v2\",", range: text.startIndex..<text.index(after: text.startIndex))
        XCTAssertThrowsError(try EEGMentalProfile.load(data: Data(duplicate.utf8)))
    }
    func testResignedInconsistentTrainingRecipeRejected() throws {
        for mode in 0..<4 {
            let data = try resigned { object in
                if mode < 2 {
                    var components = object["components"] as! [[Double]]
                    if mode == 0 { components[0] = components[0].map { $0 * 2 } }
                    else { components[1] = components[0] }
                    object["components"] = components
                } else {
                    var gaussians = object["gaussians"] as! [[String: Any]]
                    if mode == 2 {
                        var variance = gaussians[0]["variance"] as! [Double]
                        variance[0] = 0.001
                        gaussians[0]["variance"] = variance
                    } else { gaussians[0]["distance_limit"] = 1.0 }
                    object["gaussians"] = gaussians
                }
            }
            XCTAssertThrowsError(try EEGMentalProfile.load(data: data)) { error in
                guard case EEGMentalProfile.Failure.design = error else { return XCTFail("Unexpected: \(error)") }
            }
        }
    }
    func testResignedUnsupportedDesignAndProvenanceRejected() throws {
        let changes: [(inout [String: Any]) -> Void] = [
            { $0["system_control_enabled"] = true },
            { $0["feature_config_id"] = "unknown" },
            { $0["training_window_ids"] = ["duplicate", "duplicate"] },
            { $0["training_records_sha256"] = "invalid" },
            { $0["scale"] = [Double](repeating: 0, count: 70) },
            { object in var settings = object["processing_settings"] as! [String: Any]; settings.removeValue(forKey: "score_threshold"); object["processing_settings"] = settings },
            { object in var design = object["design"] as! [String: Any]; design["origin"] = "claimed-vendor-model"; object["design"] = design }
        ]
        for change in changes { XCTAssertThrowsError(try EEGMentalProfile.load(data: resigned(change))) }
    }
}
