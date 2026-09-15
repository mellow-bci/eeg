import Foundation
import XCTest
@testable import EEGCore

final class QueuedRecordingTests: XCTestCase {
    private func sample(_ index:Int) -> EEGSample {
        EEGSample(index:index,counter:index%128,receivedAt:Double(index)/128,continuous:true,
            adcWords:Array(repeating:100,count:15),
            electrodesADC:Dictionary(uniqueKeysWithValues:EEGRecordingStore.channels.map {($0,100.0)}),
            electrodesMicrovolts:nil,notificationSlot:0,recordFlag:0)
    }
    func testFinishDrainsAllAdmittedMeasurementsInOrder() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let raw=try EEGRecordingStore(directory:directory)
        let queue=DispatchQueue(label:"test.recording.order")
        let writer=try EEGQueuedRecordingStore(store:raw,queue:queue) {_,_ in XCTFail("Unexpected writer failure")}
        let url=try writer.start()
        queue.suspend()
        try writer.enqueueEvent(kind:"annotation",fields:["text":"before"])
        for index in 0..<20 {try writer.enqueue(sample:sample(index))}
        XCTAssertEqual(writer.pendingInputs,21)
        queue.resume()
        let trial=try EEGTrialEvidence(id:"trial",sessionID:"session",participantID:"synthetic",
            condition:.silentSerialSubtraction,startingNumber:613)
        try writer.appendTrialEvidence(trial)
        try writer.appendEvent(kind:"annotation",fields:["text":"after"])
        try writer.finish()
        XCTAssertEqual(writer.pendingInputs,0);XCTAssertEqual(writer.pendingPayloadBytes,0)
        XCTAssertEqual(try raw.replay(recording:url).map(\.index),Array(0..<20))
        let rows=try String(contentsOf:url).split(separator:"\n").map {
            try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]
        }
        XCTAssertEqual(rows[1]["text"] as? String,"before")
        XCTAssertEqual(rows[22]["kind"] as? String,"trial_evidence")
        XCTAssertEqual(rows[22]["sample_count_at_write"] as? Int,20)
        XCTAssertEqual(rows[23]["text"] as? String,"after")
        XCTAssertEqual(rows.last?["kind"] as? String,"summary")
    }
    func testOverloadAbortsInsteadOfFinalizingPartialCapture() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let raw=try EEGRecordingStore(directory:directory)
        let queue=DispatchQueue(label:"test.recording.overload")
        let failure=expectation(description:"abort observed")
        let writer=try EEGQueuedRecordingStore(store:raw,maximumPendingInputs:2,queue:queue) {generation,reason in
            XCTAssertEqual(generation,1);XCTAssertEqual(reason,"recording_queue_overload");failure.fulfill()
        }
        let url=try writer.start()
        queue.suspend()
        try writer.enqueue(sample:sample(0));try writer.enqueue(sample:sample(1))
        XCTAssertThrowsError(try writer.enqueue(sample:sample(2)))
        queue.resume()
        wait(for:[failure],timeout:3)
        XCTAssertThrowsError(try writer.finish())
        XCTAssertFalse(try String(contentsOf:url).contains("\"summary\""))
        XCTAssertEqual(writer.pendingInputs,0);XCTAssertEqual(writer.pendingPayloadBytes,0)
        let next=try writer.start()
        XCTAssertEqual(writer.generation,2)
        try writer.enqueue(sample:sample(0));try writer.finish()
        XCTAssertEqual(try raw.replay(recording:next).count,1)
    }
    func testEventByteBudgetRejectsBeforeQueueRetention() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let raw=try EEGRecordingStore(directory:directory)
        let queue=DispatchQueue(label:"test.recording.bytes")
        let failure=expectation(description:"byte abort")
        let writer=try EEGQueuedRecordingStore(store:raw,maximumPendingBytes:16,queue:queue) {_,_ in failure.fulfill()}
        let url=try writer.start()
        XCTAssertThrowsError(try writer.enqueueEvent(kind:"annotation",fields:["text":String(repeating:"x",count:17)]))
        wait(for:[failure],timeout:3)
        XCTAssertEqual(writer.pendingInputs,0)
        XCTAssertFalse(try String(contentsOf:url).contains("\"summary\""))
    }
    private final class BrokenOutput: EEGRecordingOutput {
        let file:FileHandle
        var writes=0
        init(_ file:FileHandle) {self.file=file}
        func write(_ data:Data) throws {
            writes+=1
            if writes>1 {throw CocoaError(.fileWriteOutOfSpace)}
            try file.write(contentsOf:data)
        }
        func synchronize() throws {try file.synchronize()}
        func close() throws {try file.close()}
        func offset() throws -> UInt64 {try file.offset()}
        func truncate(at offset:UInt64) throws {try file.truncate(atOffset:offset)}
    }
    func testAsynchronousDiskFailureAbortsAndRejectsBarrier() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let raw=try EEGRecordingStore(directory:directory)
        raw.outputFactory={BrokenOutput($0)}
        let failure=expectation(description:"disk failure")
        let writer=try EEGQueuedRecordingStore(store:raw,queue:DispatchQueue(label:"test.recording.disk")) {_,reason in
            XCTAssertTrue(reason.hasPrefix("recording_write_failed:"));failure.fulfill()
        }
        let url=try writer.start()
        try writer.enqueue(sample:sample(0))
        wait(for:[failure],timeout:3)
        XCTAssertThrowsError(try writer.appendEvent(kind:"annotation",fields:["text":"not persisted"]))
        XCTAssertThrowsError(try writer.finish())
        XCTAssertFalse(try String(contentsOf:url).contains("\"summary\""))
    }
}
