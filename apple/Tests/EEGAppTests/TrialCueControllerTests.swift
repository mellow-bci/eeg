import XCTest
import AVFAudio
import EEGCore
@testable import EEGApp

@MainActor
final class TrialCueControllerTests: XCTestCase {
    final class Speech:TrialSpeechOutput {
        weak var delegate:AVSpeechSynthesizerDelegate?
        var utterances=[AVSpeechUtterance]()
        var stops=0
        func speak(_ utterance:AVSpeechUtterance) {utterances.append(utterance)}
        func stopSpeaking(at boundary:AVSpeechBoundary)->Bool {stops+=1;return true}
    }
    final class Acquisition:TrialCueAcquisition {
        var recording=true,transportStable=true
        let session=EEGTrialSession {_ in}
        var trial:EEGTrialEvidence? {session.trial}
        var recordingClock=1.0
        var completions=[(Result<Void,Error>)->Void]()
        func trialObservationTime(uptime:Double)->Double {uptime}
        func submitTrialBegin(_ planned:EEGTrialEvidence,completion:@escaping(Result<Void,Error>)->Void) throws {
            hold(try session.prepareBegin(planned),completion:completion)
        }
        func submitTrialTransition(_ change:(inout EEGTrialEvidence,Double)throws->Void,at:Double?,completion:((Result<Void,Error>)->Void)?) throws {
            hold(try session.prepareTransition(at:at ?? recordingClock,change),completion:completion)
        }
        private func hold(_ revision:EEGTrialSession.Revision,completion:((Result<Void,Error>)->Void)?) {
            completions.append { [self] result in
                do {try session.acknowledge(revision,result:result);completion?(.success(()))}
                catch {completion?(.failure(error))}
            }
        }
        func cancelTrial(reason:String) {try? session.interrupt(reason:reason,at:recordingClock)}
        func complete(_ result:Result<Void,Error> = .success(())) {completions.removeFirst()(result)}
    }
    func testSuspensionStopDoesNotQueueAnotherUtterance() {
        let speech=Speech(),acquisition=Acquisition()
        let controller=TrialCueController(acquisition:acquisition,speech:speech)
        controller.audioCheck()
        XCTAssertEqual(speech.utterances.count,1)
        controller.stop(reason:"system_sleep",announce:false)
        XCTAssertEqual(speech.stops,1)
        XCTAssertEqual(speech.utterances.count,1)
        XCTAssertFalse(controller.busy)
        XCTAssertFalse(controller.checkCompleted)
    }
    func testAudioCheckTimeoutRejectsLateCompletionAndRequiresNewCheck() async throws {
        let speech=Speech(),acquisition=Acquisition()
        let controller=TrialCueController(acquisition:acquisition,speech:speech,uptime:{acquisition.recordingClock})
        controller.audioCheck()
        let expired=try XCTUnwrap(speech.utterances.last)
        acquisition.recordingClock += EEGTrialEvidence.maximumSpeechDuration + 0.001
        controller.tick()
        XCTAssertFalse(controller.checkCompleted)
        XCTAssertEqual(speech.stops,1)
        let stopped=try XCTUnwrap(speech.utterances.last)
        controller.speechSynthesizer(AVSpeechSynthesizer(),didFinish:expired)
        await drainCallbacks()
        XCTAssertFalse(controller.checkCompleted)
        XCTAssertTrue(controller.busy)
        controller.speechSynthesizer(AVSpeechSynthesizer(),didFinish:stopped)
        await drainCallbacks()
        XCTAssertFalse(controller.busy)
        XCTAssertFalse(controller.checkCompleted)
        controller.start(try planned(),ready:true,heard:true)
        XCTAssertTrue(acquisition.completions.isEmpty)
        try await ready(controller,speech)
        controller.stop(announce:false)
    }
    func testStartStorageTimeoutRejectsLateAcknowledgement() async throws {
        let speech=Speech(),acquisition=Acquisition()
        let controller=TrialCueController(acquisition:acquisition,speech:speech,uptime:{acquisition.recordingClock})
        try await ready(controller,speech)
        controller.start(try planned(),ready:true,heard:true)
        XCTAssertEqual(acquisition.completions.count,1)
        acquisition.recordingClock += EEGTrialEvidence.maximumSpeechDuration + 0.001
        controller.tick()
        XCTAssertFalse(controller.checkCompleted)
        XCTAssertTrue(speech.utterances.last!.speechString.contains("trial has stopped"))
        acquisition.complete()
        XCTAssertTrue(acquisition.completions.isEmpty)
        XCTAssertFalse(speech.utterances.contains { $0.speechString.contains("Begin when this instruction ends.") })
        controller.stop(announce:false)
    }
    private func planned() throws -> EEGTrialEvidence {
        try EEGTrialEvidence(id:"trial",sessionID:"session",participantID:"synthetic",condition:.neutral,startingNumber:431)
    }
    private func ready(_ controller:TrialCueController,_ speech:Speech) async throws {
        controller.audioCheck()
        let utterance=try XCTUnwrap(speech.utterances.last)
        controller.speechSynthesizer(AVSpeechSynthesizer(),didFinish:utterance)
        await withCheckedContinuation { continuation in DispatchQueue.main.async {continuation.resume()} }
        XCTAssertTrue(controller.checkCompleted)
    }
    func testInstructionWaitsForBothSavedRevisions() async throws {
        let acquisition=Acquisition(),speech=Speech()
        let controller=TrialCueController(acquisition:acquisition,speech:speech)
        try await ready(controller,speech)
        controller.start(try planned(),ready:true,heard:true)
        XCTAssertEqual(speech.utterances.count,1)
        XCTAssertTrue(controller.busy)
        acquisition.complete()
        XCTAssertEqual(speech.utterances.count,1)
        XCTAssertEqual(acquisition.completions.count,1)
        acquisition.complete()
        XCTAssertEqual(speech.utterances.count,2)
        XCTAssertTrue(speech.utterances.last!.speechString.contains("Begin when this instruction ends."))
        controller.stop()
    }
    func testStopInvalidatesLateStartAcknowledgement() async throws {
        let acquisition=Acquisition(),speech=Speech()
        let controller=TrialCueController(acquisition:acquisition,speech:speech)
        try await ready(controller,speech)
        controller.start(try planned(),ready:true,heard:true)
        controller.stop()
        acquisition.complete()
        XCTAssertEqual(speech.utterances.count,2)
        XCTAssertFalse(speech.utterances.contains {$0.speechString.contains("Begin when this instruction ends.")})
        XCTAssertFalse(controller.checkCompleted)
        XCTAssertTrue(acquisition.completions.isEmpty)
    }
    func testFailedCueRequestNeverStartsInstruction() async throws {
        let acquisition=Acquisition(),speech=Speech()
        let controller=TrialCueController(acquisition:acquisition,speech:speech)
        try await ready(controller,speech)
        controller.start(try planned(),ready:true,heard:true)
        acquisition.complete()
        acquisition.complete(.failure(EEGRecordingError.invalidData))
        XCTAssertFalse(speech.utterances.contains {$0.speechString.contains("Begin when this instruction ends.")})
        XCTAssertTrue(speech.utterances.last!.speechString.contains("trial has stopped"))
        XCTAssertFalse(controller.checkCompleted)
    }
    func testTransportLossBeforeCueAcknowledgementStopsInstruction() async throws {
        let acquisition=Acquisition(),speech=Speech()
        let controller=TrialCueController(acquisition:acquisition,speech:speech)
        try await ready(controller,speech)
        controller.start(try planned(),ready:true,heard:true)
        acquisition.complete()
        acquisition.transportStable=false
        acquisition.complete()
        XCTAssertFalse(speech.utterances.contains {$0.speechString.contains("Begin when this instruction ends.")})
        XCTAssertTrue(speech.utterances.last!.speechString.contains("trial has stopped"))
    }
    func testOldSpeechCallbackAfterStopIsIgnored() async throws {
        let acquisition=Acquisition(),speech=Speech()
        let controller=TrialCueController(acquisition:acquisition,speech:speech)
        try await ready(controller,speech)
        controller.start(try planned(),ready:true,heard:true)
        acquisition.complete();acquisition.complete()
        let oldInstruction=try XCTUnwrap(speech.utterances.last)
        controller.stop()
        controller.speechSynthesizer(AVSpeechSynthesizer(),didStart:oldInstruction)
        controller.speechSynthesizer(AVSpeechSynthesizer(),didFinish:oldInstruction)
        await withCheckedContinuation { continuation in DispatchQueue.main.async {continuation.resume()} }
        XCTAssertTrue(acquisition.completions.isEmpty)
        XCTAssertEqual(speech.utterances.count,3)
        XCTAssertEqual(acquisition.trial?.phase,.interrupted)
        XCTAssertFalse(controller.checkCompleted)
    }

    private func drainCallbacks() async {
        await withCheckedContinuation {continuation in DispatchQueue.main.async {continuation.resume()}}
    }
    private func endRequested(acknowledge:Bool=true) async throws -> (Acquisition,Speech,TrialCueController) {
        let acquisition=Acquisition(),speech=Speech()
        let controller=TrialCueController(acquisition:acquisition,speech:speech,uptime:{acquisition.recordingClock})
        try await ready(controller,speech)
        controller.start(try planned(),ready:true,heard:true)
        acquisition.complete();acquisition.complete()
        let instruction=try XCTUnwrap(speech.utterances.last)
        acquisition.recordingClock=2
        controller.speechSynthesizer(AVSpeechSynthesizer(),didStart:instruction)
        await drainCallbacks();acquisition.complete()
        acquisition.recordingClock=4
        controller.speechSynthesizer(AVSpeechSynthesizer(),didFinish:instruction)
        await drainCallbacks()
        XCTAssertEqual(acquisition.trial?.phase,.cuePlaying)
        acquisition.complete()
        XCTAssertEqual(acquisition.trial?.conditionDeadline,24)
        acquisition.recordingClock=24;controller.tick()
        XCTAssertEqual(acquisition.trial?.phase,.conditionActive)
        if acknowledge {acquisition.complete()}
        return (acquisition,speech,controller)
    }
    func testFullCueCyclePreservesObservedTimesThroughAcknowledgements() async throws {
        let (acquisition,speech,controller)=try await endRequested()
        let end=try XCTUnwrap(speech.utterances.last)
        XCTAssertTrue(end.speechString.contains("Stop the task"))
        acquisition.recordingClock=24.1
        controller.speechSynthesizer(AVSpeechSynthesizer(),didStart:end)
        await drainCallbacks();acquisition.complete()
        acquisition.recordingClock=25
        controller.speechSynthesizer(AVSpeechSynthesizer(),didFinish:end)
        await drainCallbacks()
        XCTAssertEqual(acquisition.trial?.phase,.endPlaying)
        acquisition.complete()
        XCTAssertEqual(acquisition.trial?.phase,.awaitingReport)
        XCTAssertEqual(acquisition.trial?.events.map(\.at),[1,2,4,24,24.1,25])
        XCTAssertFalse(controller.busy)
        XCTAssertEqual(controller.status,"Awaiting your report")
    }
    func testEndRequestSavePastDeadlineCannotLaunchCue() async throws {
        let (acquisition,speech,controller)=try await endRequested(acknowledge:false)
        acquisition.recordingClock=24.6;controller.tick()
        acquisition.complete()
        XCTAssertEqual(acquisition.trial?.phase,.interrupted)
        XCTAssertFalse(speech.utterances.contains {$0.speechString.contains("Please report")})
    }
    func testMissingEndSpeechStartStopsAtEndCueBound() async throws {
        let (acquisition,_,controller)=try await endRequested()
        acquisition.recordingClock=24.6;controller.tick()
        XCTAssertEqual(acquisition.trial?.phase,.interrupted)
        XCTAssertTrue(controller.status.contains("stopped"))
    }

}
