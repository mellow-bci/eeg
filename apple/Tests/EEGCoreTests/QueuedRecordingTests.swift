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
        XCTAssertEqual(writer.statistics.peakPendingInputs,21)
        XCTAssertEqual(writer.statistics.admittedInputs,21)
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
        let telemetry=rows[rows.count-2]
        XCTAssertEqual(telemetry["kind"] as? String,"writer_statistics")
        XCTAssertEqual(telemetry["written_inputs"] as? String,"21")
        XCTAssertEqual(telemetry["scope"] as? String,"asynchronous_inputs_only")
        XCTAssertEqual(writer.statistics.writtenInputs,21)
        XCTAssertEqual(writer.statistics.discardedInputs,0)
        XCTAssertGreaterThanOrEqual(writer.statistics.maximumQueueWaitSeconds,0)
        XCTAssertGreaterThanOrEqual(writer.statistics.maximumWriteSeconds,0)
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
        queue.sync {}
        XCTAssertThrowsError(try writer.finish())
        XCTAssertFalse(try String(contentsOf:url).contains("\"summary\""))
        XCTAssertEqual(writer.pendingInputs,0);XCTAssertEqual(writer.pendingPayloadBytes,0)
        XCTAssertEqual(writer.statistics.discardedInputs,2)
        XCTAssertTrue(writer.statistics.failed)
        let next=try writer.start()
        XCTAssertEqual(writer.statistics.admittedInputs,0)
        XCTAssertEqual(writer.statistics.maximumWriteSeconds,0)
        XCTAssertFalse(writer.statistics.failed)
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
        queue.sync {}
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
        let queue=DispatchQueue(label:"test.recording.disk")
        let writer=try EEGQueuedRecordingStore(store:raw,queue:queue) {_,reason in
            XCTAssertTrue(reason.hasPrefix("recording_write_failed:"));failure.fulfill()
        }
        let url=try writer.start()
        try writer.enqueue(sample:sample(0))
        wait(for:[failure],timeout:3)
        queue.sync {}
        XCTAssertEqual(writer.statistics.failedWrites,1)
        XCTAssertEqual(writer.statistics.writtenInputs,0)
        XCTAssertTrue(writer.statistics.failed)
        XCTAssertThrowsError(try writer.appendEvent(kind:"annotation",fields:["text":"not persisted"]))
        XCTAssertThrowsError(try writer.finish())
        XCTAssertFalse(try String(contentsOf:url).contains("\"summary\""))
    }
    private final class StalledOutput: EEGRecordingOutput {
        let file:FileHandle
        let entered:DispatchSemaphore
        let release:DispatchSemaphore
        var writes=0
        init(_ file:FileHandle,entered:DispatchSemaphore,release:DispatchSemaphore) {
            self.file=file;self.entered=entered;self.release=release
        }
        func write(_ data:Data) throws {
            writes+=1
            if writes==2 {
                entered.signal()
                // A deadline makes a regression fail rather than hang the suite.
                guard release.wait(timeout:.now()+5) == .success else {throw CocoaError(.fileWriteUnknown)}
            }
            try file.write(contentsOf:data)
        }
        func synchronize() throws {try file.synchronize()}
        func close() throws {try file.close()}
        func offset() throws -> UInt64 {try file.offset()}
        func truncate(at offset:UInt64) throws {try file.truncate(atOffset:offset)}
    }
    func testOverloadNotifiesBeforeStalledWriteCanClose() throws {
        try checkStalledAbort(overload:true)
    }
    func testExplicitAbortReturnsBeforeStalledWriteCanClose() throws {
        try checkStalledAbort(overload:false)
    }
    private func checkStalledAbort(overload:Bool) throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let raw=try EEGRecordingStore(directory:directory)
        let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
        raw.outputFactory={StalledOutput($0,entered:entered,release:release)}
        let queue=DispatchQueue(label:"test.recording.stall")
        let notified=DispatchSemaphore(value:0)
        let writer=try EEGQueuedRecordingStore(store:raw,maximumPendingInputs:1,queue:queue) {_,reason in
            XCTAssertTrue(overload);XCTAssertEqual(reason,"recording_queue_overload");notified.signal()
        }
        let url=try writer.start()
        defer {release.signal();queue.sync {}}
        try writer.enqueue(sample:sample(0))
        XCTAssertEqual(entered.wait(timeout:.now()+2),.success)
        if overload {
            XCTAssertThrowsError(try writer.enqueue(sample:sample(1)))
            XCTAssertEqual(notified.wait(timeout:.now()+1),.success)
        } else {writer.abort()}
        // These checks execute while the real file output is still held. They
        // prove rejection/notification does not wait for writer cleanup.
        XCTAssertTrue(writer.statistics.cleanupPending)
        XCTAssertEqual(writer.pendingInputs,1)
        XCTAssertEqual(writer.statistics.failed,overload)
        XCTAssertThrowsError(try writer.start()) { error in
            guard case EEGQueuedRecordingStore.Failure.cleanupPending=error else {return XCTFail("Wrong rejection: \(error)")}
        }
        XCTAssertThrowsError(try writer.finish())
        XCTAssertThrowsError(try writer.appendEvent(kind:"annotation",fields:[:]))
        XCTAssertThrowsError(try writer.enqueue(sample:sample(2)))
        release.signal();queue.sync {}
        XCTAssertFalse(writer.statistics.cleanupPending)
        XCTAssertEqual(writer.pendingInputs,0)
        XCTAssertFalse(try String(contentsOf:url).contains("\"summary\""))
        // The in-flight write can finish; it must never make this file complete.
        XCTAssertEqual(writer.statistics.writtenInputs,1)
        raw.outputFactory={EEGFileRecordingOutput($0)}
        _=try writer.start();try writer.finish()
        XCTAssertEqual(writer.generation,2)
    }

    func testFinalizationCanTransferOffAdmissionExecutorAndDrain() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let raw=try EEGRecordingStore(directory:directory)
        let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
        raw.outputFactory={StalledOutput($0,entered:entered,release:release)}
        let writer=try EEGQueuedRecordingStore(store:raw,queue:DispatchQueue(label:"test.finish.writer")) {_,_ in
            XCTFail("Unexpected finalization failure")
        }
        let url=try writer.start()
        try writer.enqueue(sample:sample(0))
        XCTAssertEqual(entered.wait(timeout:.now()+2),.success)
        let finalizer=DispatchQueue(label:"test.finish.control")
        defer {release.signal();finalizer.sync {}}
        let started=DispatchSemaphore(value:0),completed=DispatchSemaphore(value:0)
        // Acquisition ceases admission before transferring this final control.
        finalizer.async {
            started.signal()
            do {try writer.finish()} catch {XCTFail("Finish failed: \(error)")}
            completed.signal()
        }
        XCTAssertEqual(started.wait(timeout:.now()+2),.success)
        XCTAssertEqual(completed.wait(timeout:.now()+0.02),.timedOut)
        XCTAssertEqual(writer.statistics.pendingInputs,1)
        release.signal()
        XCTAssertEqual(completed.wait(timeout:.now()+2),.success)
        XCTAssertEqual(try raw.replay(recording:url).count,1)
        XCTAssertTrue(try String(contentsOf:url).contains("\"summary\""))
        XCTAssertEqual(writer.statistics.pendingInputs,0)
    }

    private final class SyncGateOutput: EEGRecordingOutput {
        let file:FileHandle, entered:DispatchSemaphore, release:DispatchSemaphore
        let fail:Bool
        init(_ file:FileHandle,entered:DispatchSemaphore,release:DispatchSemaphore,fail:Bool) {
            self.file=file;self.entered=entered;self.release=release;self.fail=fail
        }
        func write(_ data:Data) throws {try file.write(contentsOf:data)}
        func synchronize() throws {
            entered.signal()
            guard release.wait(timeout:.now()+5) == .success else {throw CocoaError(.fileWriteUnknown)}
            if fail {throw CocoaError(.fileWriteOutOfSpace)}
            try file.synchronize()
        }
        func close() throws {try file.close()}
        func offset() throws -> UInt64 {try file.offset()}
        func truncate(at offset:UInt64) throws {try file.truncate(atOffset:offset)}
    }
    func testAcknowledgedEventWaitsForSynchronization() throws {try checkAcknowledgement(fail:false)}
    func testAcknowledgedEventReportsSynchronizationFailure() throws {try checkAcknowledgement(fail:true)}
    func testQueuedTrialWaitsForSynchronization() throws {try checkAcknowledgement(fail:false,trial:true)}
    func testQueuedTrialReportsSynchronizationFailure() throws {try checkAcknowledgement(fail:true,trial:true)}
    private func checkAcknowledgement(fail:Bool,trial:Bool=false) throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let raw=try EEGRecordingStore(directory:directory)
        let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0),done=DispatchSemaphore(value:0)
        raw.outputFactory={SyncGateOutput($0,entered:entered,release:release,fail:fail)}
        let queue=DispatchQueue(label:"test.ack.writer")
        let writer=try EEGQueuedRecordingStore(store:raw,queue:queue) {_,_ in XCTAssertTrue(fail)}
        let url=try writer.start()
        defer {release.signal();writer.abort();queue.sync {}}
        let callback:(Result<Void,Error>)->Void = { result in
            switch result {
            case .success: XCTAssertFalse(fail)
            case .failure: XCTAssertTrue(fail)
            }
            done.signal()
        }
        if trial {
            try writer.enqueueTrialEvidence(EEGTrialEvidence(id:"trial",sessionID:"session",participantID:"synthetic",
                condition:.neutral,startingNumber:431),onPersisted:callback)
        } else {try writer.enqueueEvent(kind:"annotation",fields:["text":"requires acknowledgement"],onPersisted:callback)}
        XCTAssertEqual(entered.wait(timeout:.now()+2),.success)
        XCTAssertEqual(done.wait(timeout:.now()+0.02),.timedOut)
        release.signal()
        XCTAssertEqual(done.wait(timeout:.now()+2),.success)
        queue.sync {}
        XCTAssertEqual(writer.statistics.failed,fail)
        XCTAssertEqual(writer.statistics.writtenInputs,fail ? 0:1)
        // Neither acknowledgement nor a partially written failed event means
        // this recording has been finalized.
        XCTAssertFalse(try String(contentsOf:url).contains("\"summary\""))
    }
    func testAbortedAcknowledgedEventCompletesWithFailure() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let queue=DispatchQueue(label:"test.ack.abort")
        let writer=try EEGQueuedRecordingStore(store:EEGRecordingStore(directory:directory),queue:queue) {_,_ in XCTFail()}
        _=try writer.start();queue.suspend()
        let completed=expectation(description:"aborted acknowledgement")
        try writer.enqueueEvent(kind:"annotation",fields:[:]) { result in
            guard case .failure = result else {return XCTFail("Aborted event acknowledged")}
            completed.fulfill()
        }
        writer.abort();queue.resume()
        wait(for:[completed],timeout:2);queue.sync {}
        XCTAssertEqual(writer.statistics.discardedInputs,1)
    }

    func testQueuedTrialPreservesSampleBoundaryAndRejectsDuplicateRevision() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let raw=try EEGRecordingStore(directory:directory)
        let queue=DispatchQueue(label:"test.trial.queue")
        let failure=expectation(description:"invalid revision abort")
        let writer=try EEGQueuedRecordingStore(store:raw,queue:queue) {_,_ in failure.fulfill()}
        let url=try writer.start()
        let planned=try EEGTrialEvidence(id:"trial",sessionID:"session",participantID:"synthetic",condition:.neutral,startingNumber:431)
        let persisted=expectation(description:"trial persisted")
        for index in 0..<3 {try writer.enqueue(sample:sample(index))}
        try writer.enqueueTrialEvidence(planned) { result in
            if case .failure(let error)=result {XCTFail("Trial failed: \(error)")}
            persisted.fulfill()
        }
        wait(for:[persisted],timeout:2)
        let rows=try String(contentsOf:url).split(separator:"\n").map {
            try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]
        }
        XCTAssertEqual(rows.last?["kind"] as? String,"trial_evidence")
        XCTAssertEqual(rows.last?["sample_count_at_write"] as? Int,3)
        let rejected=expectation(description:"duplicate rejected")
        try writer.enqueueTrialEvidence(planned) { result in
            if case .success=result {XCTFail("Duplicate revision accepted")}
            rejected.fulfill()
        }
        wait(for:[failure,rejected],timeout:2);queue.sync {}
        XCTAssertThrowsError(try writer.finish())
        XCTAssertFalse(try String(contentsOf:url).contains("\"summary\""))
    }

}
