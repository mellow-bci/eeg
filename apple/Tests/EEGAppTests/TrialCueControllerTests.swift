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
        XCTAssertTrue(speech.utterances.last!.speechString.contains("Starting number"))
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
        XCTAssertFalse(speech.utterances.contains {$0.speechString.contains("Starting number")})
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
        XCTAssertFalse(speech.utterances.contains {$0.speechString.contains("Starting number")})
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
        XCTAssertFalse(speech.utterances.contains {$0.speechString.contains("Starting number")})
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

}
