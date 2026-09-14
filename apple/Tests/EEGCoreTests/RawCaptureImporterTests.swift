import XCTest
@testable import EEGCore

final class RawCaptureImporterTests:XCTestCase {
    func testActualRawCaptureImportsThroughDecoderAndReplays() throws {
        let repo=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture=repo.appendingPathComponent("archive/current-state/ble-capture.json")
        guard FileManager.default.fileExists(atPath:fixture.path) else {throw XCTSkip("Hydrate private fixture using git lfs pull")}
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:dir)}
        let result=try EEGRawCaptureImporter.importCapture(fixture,directory:dir)
        XCTAssertEqual(result.sampleCount,1588)
        let store=try EEGRecordingStore(directory:dir)
        let info=try XCTUnwrap(store.inventory().first)
        XCTAssertTrue(info.complete);XCTAssertFalse(info.corrupt)
        XCTAssertEqual(try store.replay(recording:result.url,limit:1588).count,1588)
    }
    func testMalformedInputCannotCreateSuccessfulRecording() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:dir)}
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let source=dir.appendingPathComponent("invalid.json")
        try Data("{}".utf8).write(to:source)
        XCTAssertThrowsError(try EEGRawCaptureImporter.importCapture(source,directory:dir.appendingPathComponent("recordings")))
        XCTAssertTrue(try EEGRecordingStore(directory:dir.appendingPathComponent("recordings")).inventory().isEmpty)
    }
}
