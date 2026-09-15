import XCTest
@testable import EEGCore

final class RecordingCompletionTests: XCTestCase {
    private enum Fault: Error { case injected }
    private final class Output: EEGRecordingOutput {
        let file: EEGFileRecordingOutput
        let failWrite: Bool
        let failRollback: Bool
        var summary = false
        var failed = false
        init(_ file: FileHandle, failWrite: Bool, failRollback: Bool = false) {
            self.file=EEGFileRecordingOutput(file);self.failWrite=failWrite;self.failRollback=failRollback
        }
        func write(_ data: Data) throws {
            if String(decoding:data,as:UTF8.self).contains("\"summary\"") {
                summary=true
                if failWrite { try file.write(Data(data.prefix(data.count/2)));failed=true;throw Fault.injected }
            }
            try file.write(data)
        }
        func synchronize() throws {
            if summary && !failed { failed=true;throw Fault.injected }
            try file.synchronize()
        }
        func close() throws { try file.close() }
        func offset() throws -> UInt64 { try file.offset() }
        func truncate(at offset: UInt64) throws {
            if failRollback { throw Fault.injected }
            try file.truncate(at:offset)
        }
    }
    func testPartialSummaryAndFlushFailureRemainIncomplete() throws {
        for writeFailure in [true,false] {
            let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at:root) }
            let store=try EEGRecordingStore(directory:root)
            store.outputFactory={ Output($0,failWrite:writeFailure) }
            let file=try store.start()
            try store.appendEvent(kind:"annotation",fields:["text":"retained"])
            XCTAssertThrowsError(try store.finish())
            let info=try XCTUnwrap(store.inventory().first)
            XCTAssertFalse(info.complete);XCTAssertFalse(info.corrupt)
            XCTAssertTrue(try String(contentsOf:file).contains("retained"))
            XCTAssertFalse(try String(contentsOf:file).contains("summary"))
            XCTAssertThrowsError(try store.finish())
            XCTAssertThrowsError(try store.analysisWindows(recording:file) { _ in })
        }
    }
    func testRollbackFailureReportsUncertainty() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store=try EEGRecordingStore(directory:root)
        store.outputFactory={ Output($0,failWrite:true,failRollback:true) }
        _ = try store.start()
        XCTAssertThrowsError(try store.finish()) { XCTAssertTrue($0 is EEGRecordingCompletionFailure) }
        XCTAssertThrowsError(try store.finish())
    }
}
