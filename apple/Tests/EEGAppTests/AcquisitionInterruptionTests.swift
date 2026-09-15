import XCTest
import EEGCore
import CoreBluetooth
@testable import EEGApp

@MainActor
final class AcquisitionInterruptionTests:XCTestCase {
    func testBluetoothCancellationRejectsLateWorkUntilTerminalCallback() {
        var gate=BluetoothSessionGate()
        let first=UUID(),other=UUID()
        XCTAssertFalse(gate.accepts(first))
        XCTAssertTrue(gate.begin(first))
        XCTAssertTrue(gate.accepts(first))
        XCTAssertFalse(gate.accepts(other))
        gate.cancel()
        XCTAssertFalse(gate.accepts(first))
        XCTAssertFalse(gate.begin(first))
        XCTAssertFalse(gate.begin(other))
        XCTAssertFalse(gate.finish(other))
        XCTAssertFalse(gate.accepts(first))
        XCTAssertTrue(gate.finish(first))
        XCTAssertFalse(gate.finish(first))
        XCTAssertTrue(gate.begin(other))
        XCTAssertFalse(gate.accepts(first))
        XCTAssertFalse(gate.finish(first))
        XCTAssertTrue(gate.accepts(other))
        XCTAssertTrue(gate.finish(other))
        XCTAssertTrue(gate.begin(first))
        XCTAssertTrue(gate.accepts(first))
    }
    func testNewRecordingPersistsOneExplicitClockAnchor() async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let model=AcquisitionModel(storageDirectory:directory)
        model.ready=true;model.startRecording();model.stopRecording()
        try await waitUntil {!model.finalizingRecording}
        let file=try XCTUnwrap(FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil).first {$0.pathExtension == "jsonl"})
        let events=try String(contentsOf:file).split(separator:"\n").map {try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]}
        let anchors=events.filter {$0["kind"] as? String == "recording_clock_anchor"}
        XCTAssertEqual(anchors.count,1)
        let anchor=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(try XCTUnwrap(anchors.first?["json"] as? String).utf8)) as? [String:Any])
        XCTAssertEqual(anchor["schema"] as? String,"eeg.recording-clock-anchor.v1")
        let before=try XCTUnwrap(anchor["receiptBefore"] as? Double),after=try XCTUnwrap(anchor["receiptAfter"] as? Double)
        XCTAssertGreaterThanOrEqual(before,0);XCTAssertGreaterThanOrEqual(after,before)
        XCTAssertEqual(anchor["wallClockAccuracy"] as? String,"unmeasured")
        XCTAssertEqual(events.last?["kind"] as? String,"summary")
    }
    private func waitUntil(_ condition:()->Bool) async throws {
        for _ in 0..<200 {
            if condition() {return}
            try await Task.sleep(nanoseconds:10_000_000)
        }
        XCTFail("Timed out waiting for local persistence")
    }
    func testSuspensionStopsRecordingAndPersistsReason() async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let model=AcquisitionModel(storageDirectory:directory)
        model.ready=true;model.transportStable=true;model.startRecording()
        try model.commitTrialPlan(participantID:"synthetic",sessionID:"suspension")
        try await waitUntil {model.trialPlan != nil}
        try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
            do {try model.submitTrialBegin(model.nextPlannedTrial()) {continuation.resume(with:$0)}}
            catch {continuation.resume(throwing:error)}
        }
        model.prepareForSuspension(reason:"system_sleep")
        XCTAssertFalse(model.ready);XCTAssertFalse(model.recording);XCTAssertFalse(model.transportStable)
        XCTAssertFalse(model.trialCues.busy)
        try await waitUntil {!model.finalizingRecording && !model.savingTrialRevision}
        XCTAssertEqual(model.trial?.phase,.interrupted)
        XCTAssertEqual(model.trial?.reviewReason,"system_sleep")
        let files=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil).filter {$0.pathExtension=="jsonl"}
        let recovered=try EEGRecordingStore(directory:directory).recoveredTrials(recording:XCTUnwrap(files.first))
        XCTAssertEqual(recovered.first?.reviewReason,"system_sleep")
    }
    func testRepeatedCancelDrainsOneInterruptionBeforeSummary() async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let model=AcquisitionModel(storageDirectory:directory)
        // Synthetic lifecycle readiness only. Never initialize Bluetooth, emit
        // audio, or assert physiological validity in this test.
        model.ready=true;model.transportStable=true
        model.startRecording()
        XCTAssertTrue(model.recording)
        try model.commitTrialPlan(participantID:"synthetic",sessionID:"isolated-test")
        try await waitUntil {model.trialPlan != nil}
        let planned=try model.nextPlannedTrial()
        try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
            do {try model.submitTrialBegin(planned) {continuation.resume(with:$0)}}
            catch {continuation.resume(throwing:error)}
        }
        model.cancelTrial(reason:"operator_stopped")
        XCTAssertTrue(model.savingTrialRevision)
        model.cancelTrial(reason:"repeated_stop")
        model.stopRecording()
        XCTAssertTrue(model.finalizingRecording)
        try await waitUntil {!model.finalizingRecording && !model.savingTrialRevision}
        XCTAssertFalse(model.recording)
        XCTAssertEqual(model.trial?.phase,.interrupted)
        XCTAssertEqual(model.trial?.reviewReason,"operator_stopped")
        let files=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)
            .filter {$0.pathExtension=="jsonl"}
        let url=try XCTUnwrap(files.first)
        XCTAssertEqual(files.count,1)
        let rows=try String(contentsOf:url).split(separator:"\n").map {
            try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]
        }
        let revisions=rows.filter {$0["kind"] as? String == "trial_evidence"}
        XCTAssertEqual(revisions.count,2)
        let last=try XCTUnwrap(revisions.last?["evidence"])
        let recovered=try EEGTrialEvidence.recover(JSONSerialization.data(withJSONObject:last))
        XCTAssertEqual(recovered.phase,.interrupted)
        XCTAssertEqual(recovered.reviewReason,"operator_stopped")
        XCTAssertEqual(rows.last?["kind"] as? String,"summary")
        XCTAssertTrue(model.events.contains {$0.contains("Recording finalized")})
    }
    func testUnavailableBluetoothStatesStopAndPersistInterruption() async throws {
        let states: [(CBManagerState,String)] = [(.poweredOff,"bluetooth_powered_off"),(.unauthorized,"bluetooth_unauthorized"),(.unsupported,"bluetooth_unsupported"),(.resetting,"bluetooth_resetting"),(.unknown,"bluetooth_unknown")]
        for (state,reason) in states {
            let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer {try? FileManager.default.removeItem(at:directory)}
            let model=AcquisitionModel(storageDirectory:directory)
            model.ready=true;model.transportStable=true;model.startRecording()
            try model.commitTrialPlan(participantID:"synthetic",sessionID:"radio-state")
            try await waitUntil {model.trialPlan != nil}
            let planned=try model.nextPlannedTrial()
            try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
                do {try model.submitTrialBegin(planned) {continuation.resume(with:$0)}}
                catch {continuation.resume(throwing:error)}
            }
            model.handleBluetoothState(state)
            XCTAssertFalse(model.ready);XCTAssertFalse(model.transportStable);XCTAssertFalse(model.recording)
            try await waitUntil {!model.finalizingRecording && !model.savingTrialRevision}
            XCTAssertEqual(model.trial?.phase,.interrupted)
            XCTAssertEqual(model.trial?.reviewReason,reason)
            let files=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil).filter {$0.pathExtension=="jsonl"}
            let trials=try EEGRecordingStore(directory:directory).recoveredTrials(recording:XCTUnwrap(files.first))
            XCTAssertEqual(trials.first?.reviewReason,reason)
        }
    }
    func testStopDuringPendingStartCannotFinalizeOrPublishStart() async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let model=AcquisitionModel(storageDirectory:directory)
        model.ready=true;model.transportStable=true;model.startRecording()
        try model.commitTrialPlan(participantID:"synthetic",sessionID:"cancel-start")
        try await waitUntil {model.trialPlan != nil}
        let completed=expectation(description:"invalidated start")
        try model.submitTrialBegin(model.nextPlannedTrial()) { result in
            if case .success=result {XCTFail("Cancelled start published")}
            completed.fulfill()
        }
        model.stopRecording()
        XCTAssertFalse(model.recording)
        XCTAssertFalse(model.finalizingRecording)
        await fulfillment(of:[completed],timeout:2)
        XCTAssertEqual(model.trialsStarted,0)
        XCTAssertEqual(model.trial?.phase,.interrupted)
        let files=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)
            .filter {$0.pathExtension=="jsonl"}
        XCTAssertEqual(files.count,1)
        XCTAssertFalse(try String(contentsOf:XCTUnwrap(files.first)).contains("\"summary\""))
        XCTAssertFalse(model.events.contains {$0.contains("Recording finalized")})
    }

}
