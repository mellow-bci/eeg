import XCTest
@testable import EEGCore

final class ProcessingSettingsTests: XCTestCase {
    func testCLICompatibleDefaultsAndNullBudget() throws {
        let settings = ProcessingSettings()
        let data = try settings.jsonData()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["schema", "max_training_windows", "selected_features", "pca_components", "variance_floor", "score_threshold", "margin_threshold", "persistence_windows"]))
        XCTAssertTrue(object["max_training_windows"] is NSNull)
        XCTAssertEqual(object["schema"] as? String, "eeg.processing-settings.v1")
        XCTAssertEqual(try JSONDecoder().decode(ProcessingSettings.self, from: data), settings)
        XCTAssertEqual(try JSONDecoder().decode(ProcessingSettings.self, from: Data("{}".utf8)), settings)
    }
    func testPartialOverridesAndInvalidDocuments() throws {
        let override = try JSONDecoder().decode(ProcessingSettings.self, from: Data("{\"selected_features\":12,\"pca_components\":4,\"max_training_windows\":200}".utf8))
        XCTAssertEqual(override.selectedFeatures, 12); XCTAssertEqual(override.pcaComponents, 4)
        XCTAssertEqual(override.maxTrainingWindows, 200)
        for json in ["{\"unknown\":1}", "{\"schema\":\"future\"}", "{\"score_threshold\":0}",
                     "{\"margin_threshold\":1.1}", "{\"variance_floor\":0}", "{\"selected_features\":71}",
                     "{\"selected_features\":4}", "{\"max_training_windows\":0}",
                     "{\"persistence_windows\":null}", "{\"selected_features\":true}", "{\"pca_components\":1.2}"] {
            XCTAssertThrowsError(try JSONDecoder().decode(ProcessingSettings.self, from: Data(json.utf8)), json)
        }
        var invalid = ProcessingSettings(); invalid.varianceFloor = .nan
        XCTAssertThrowsError(try invalid.jsonData())
    }
    func testAtomicPersistenceInvalidSaveDoesNotClobber() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ProcessingSettingsStore(directory: root)
        XCTAssertEqual(try store.load(), ProcessingSettings())
        var settings = ProcessingSettings(); settings.persistenceWindows = 4
        try store.save(settings)
        XCTAssertEqual(try store.load(), settings)
        let previous = try Data(contentsOf: store.file)
        settings.maxTrainingWindows = -1
        XCTAssertThrowsError(try store.save(settings))
        XCTAssertEqual(try Data(contentsOf: store.file), previous)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: store.file.path)[.posixPermissions] as? Int, 0o600)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["processing-settings.json"])
    }
    func testCorruptOversizedAndSymlinkReadRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ProcessingSettingsStore(directory: root)
        try Data("broken".utf8).write(to: store.file)
        XCTAssertThrowsError(try store.load())
        try Data(repeating: 32, count: ProcessingSettingsStore.maximumBytes + 1).write(to: store.file)
        XCTAssertThrowsError(try store.load())
        let target = root.appendingPathComponent("outside.json")
        try ProcessingSettings().jsonData().write(to: target)
        try FileManager.default.removeItem(at: store.file)
        try FileManager.default.createSymbolicLink(at: store.file, withDestinationURL: target)
        XCTAssertThrowsError(try store.load())
    }
}
