import XCTest
import Foundation
@testable import EEGCore

final class ProfileStoreTests: XCTestCase {
    private func fixture() throws -> EEGProfileCreation.Artifact {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Fixtures/spectrum/mental-profile.json"))
        return EEGProfileCreation.Artifact(data: data, profile: try EEGMentalProfile.load(data: data))
    }
    func testSavedProfileIsRevalidatedAndNeverReplaced() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EEGProfileStore(directory: directory), artifact = try fixture()
        XCTAssertTrue(try store.entries().isEmpty)
        XCTAssertEqual(try store.save(artifact).id, artifact.profile.id)
        XCTAssertEqual(try store.entries().map(\.id), [artifact.profile.id])
        XCTAssertEqual(try store.load(artifact.profile.id).participantID, artifact.profile.participantID)
        XCTAssertThrowsError(try store.save(artifact))
        let file = directory.appendingPathComponent(artifact.profile.id + ".json")
        XCTAssertEqual(try Data(contentsOf: file), artifact.data)
        try Data("{}".utf8).write(to: file)
        XCTAssertThrowsError(try store.load(artifact.profile.id))
    }
    func testIdentityTraversalAndSymlinkAreRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EEGProfileStore(directory: directory), artifact = try fixture()
        let otherID = String(repeating: "a", count: 64)
        try artifact.data.write(to: directory.appendingPathComponent(otherID + ".json"))
        XCTAssertThrowsError(try store.load(otherID))
        XCTAssertThrowsError(try store.load("../profile"))
        let link = directory.appendingPathComponent(artifact.profile.id + ".json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory.appendingPathComponent(otherID + ".json"))
        XCTAssertThrowsError(try store.load(artifact.profile.id))
        XCTAssertThrowsError(try store.entries())
    }
    func testBoundedReadRejectsOversizeAndDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try EEGProfileStore.readDocument(directory))
        let file = directory.appendingPathComponent("oversize.json")
        try Data(repeating: 32, count: 8 * 1024 * 1024 + 1).write(to: file)
        XCTAssertThrowsError(try EEGProfileStore.readDocument(file))
    }
}
