import Foundation
import XCTest
@testable import EEGCore

final class TrialSessionTests: XCTestCase {
    private func planned() throws -> EEGTrialEvidence {
        try EEGTrialEvidence(id: "trial", sessionID: "session", participantID: "synthetic", condition: .neutral, startingNumber: 431)
    }
    func testPersistsBeforePublicationAndInterruptsOnlyOnce() throws {
        var revisions: [EEGTrialEvidence] = []
        let session = EEGTrialSession { revisions.append($0) }
        try session.begin(planned())
        XCTAssertThrowsError(try session.begin(planned()))
        try session.transition(at: 1) { try $0.requestCue(at: $1, participantReady: true, audioCheckHeard: true, transportStable: true, recordingActive: true) }
        try session.interrupt(reason: "counter_discontinuity", at: 2)
        try session.interrupt(reason: "recording_stopped", at: 3)
        XCTAssertEqual(revisions.map(\.phase), [.planned, .cueRequested, .interrupted])
        XCTAssertFalse(session.active)
        XCTAssertThrowsError(try XCTUnwrap(session.trial).datasetTrial())
        XCTAssertEqual(session.trial?.reviewReason, "counter_discontinuity")
    }
    func testFailedSinkCannotPublishOrRetrySuccessfulTransition() throws {
        var writes = 0
        let session = EEGTrialSession { _ in
            writes += 1
            if writes == 2 { throw EEGRecordingError.invalidData }
        }
        try session.begin(planned())
        XCTAssertThrowsError(try session.transition(at: 1) { try $0.requestCue(at: $1, participantReady: true, audioCheckHeard: true, transportStable: true, recordingActive: true) })
        XCTAssertEqual(session.trial?.phase, .interrupted)
        XCTAssertEqual(session.trial?.reviewReason, "evidence_persistence_failed")
        XCTAssertNotNil(session.persistenceFailure)
        XCTAssertFalse(session.active)
        XCTAssertThrowsError(try session.begin(planned()))
        XCTAssertThrowsError(try session.transition(at: 2) { try $0.cueStarted(at: $1) })
        XCTAssertEqual(writes, 2)
    }
    func testInvalidTransitionDoesNotWriteOrPoisonRecording() throws {
        var writes = 0
        let session = EEGTrialSession { _ in writes += 1 }
        try session.begin(planned())
        XCTAssertThrowsError(try session.transition(at: 1) { try $0.cueCompleted(at: $1) })
        XCTAssertEqual(writes, 1)
        XCTAssertNil(session.persistenceFailure)
        XCTAssertEqual(session.trial?.phase, .planned)
        try session.interrupt(reason: "operator_cancelled", at: 2)
        XCTAssertEqual(writes, 2)
    }
    func testPreparedRevisionIsUnpublishedUntilAcknowledged() throws {
        let session=EEGTrialSession {_ in XCTFail("Prepare must not invoke synchronous storage")}
        let revision=try session.prepareBegin(planned())
        XCTAssertNil(session.trial);XCTAssertNotNil(session.pending)
        XCTAssertThrowsError(try session.prepareBegin(planned()))
        try session.acknowledge(revision,result:.success(()))
        XCTAssertEqual(session.trial?.phase,.planned);XCTAssertNil(session.pending)
        XCTAssertThrowsError(try session.acknowledge(revision,result:.success(())))
        XCTAssertEqual(session.trial?.phase,.planned)
    }
    func testPendingInterruptionCannotBeResurrectedByLateSuccess() throws {
        let session=EEGTrialSession {_ in}
        try session.begin(planned())
        let revision=try session.prepareTransition(at:1) {
            try $0.requestCue(at:$1,participantReady:true,audioCheckHeard:true,transportStable:true,recordingActive:true)
        }
        XCTAssertEqual(session.trial?.phase,.planned)
        XCTAssertThrowsError(try session.interrupt(reason:"operator_stopped",at:2))
        XCTAssertEqual(session.trial?.phase,.interrupted)
        XCTAssertEqual(session.trial?.reviewReason,"operator_stopped")
        XCTAssertNotNil(session.persistenceFailure);XCTAssertNil(session.pending)
        XCTAssertThrowsError(try session.acknowledge(revision,result:.success(())))
        XCTAssertEqual(session.trial?.phase,.interrupted)
        XCTAssertThrowsError(try session.prepareBegin(planned()))
        XCTAssertThrowsError(try XCTUnwrap(session.trial).datasetTrial())
    }
    func testFailedInitialAcknowledgementCannotEnableTrial() throws {
        let session=EEGTrialSession {_ in}
        let revision=try session.prepareBegin(planned())
        XCTAssertThrowsError(try session.acknowledge(revision,result:.failure(EEGRecordingError.invalidData)))
        XCTAssertNil(session.trial);XCTAssertNotNil(session.persistenceFailure)
        XCTAssertNil(session.pending)
        XCTAssertThrowsError(try session.acknowledge(revision,result:.success(())))
    }

    func testSpeechObservationTimesSurviveDeferredAcknowledgement() throws {
        let session=EEGTrialSession {_ in}
        try session.begin(planned())
        try session.transition(at:1) {try $0.requestCue(at:$1,participantReady:true,audioCheckHeard:true,transportStable:true,recordingActive:true)}
        let start=try session.prepareTransition(at:2) {try $0.cueStarted(at:$1)}
        XCTAssertThrowsError(try session.prepareTransition(at:3) {try $0.cueCompleted(at:$1)})
        XCTAssertEqual(session.trial?.phase,.cueRequested)
        try session.acknowledge(start,result:.success(()))
        let finish=try session.prepareTransition(at:4) {try $0.cueCompleted(at:$1)}
        XCTAssertNil(session.trial?.cueCompletedAt)
        try session.acknowledge(finish,result:.success(()))
        XCTAssertEqual(session.trial?.cueCompletedAt,4)
        XCTAssertEqual(session.trial?.conditionDeadline,24)
        XCTAssertEqual(session.trial?.events.map(\.at),[1,2,4])
    }

    func testFractionalInterruptionSurvivesJSONContainerRoundTrip() throws {
        for index in 1...100 {
            var trial=try planned()
            let at=(100000.123456789+Double(index)*0.000132)-100000.1
            try trial.interrupt(reason:"operator_stopped",at:at)
            let object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(trial))
            let data=try JSONSerialization.data(withJSONObject:object)
            let recovered:EEGTrialEvidence
            do {recovered=try EEGTrialEvidence.recover(data)} catch {
                XCTFail("Recovery failed at \(at): \(error)");return
            }
            struct Event:Decodable {let at:Double}
            struct Received:Decodable {let events:[Event]}
            let received=try JSONDecoder().decode(Received.self,from:data)
            XCTAssertEqual(recovered.events.last?.at,received.events.last?.at)
        }
    }

    func testRecoveryStillRejectsUnknownFieldsAndNumericBooleans() throws {
        let original=try JSONSerialization.jsonObject(with:JSONEncoder().encode(planned())) as! [String:Any]
        var changed=original;changed["accepted"]=0
        XCTAssertThrowsError(try EEGTrialEvidence.recover(JSONSerialization.data(withJSONObject:changed)))
        changed=original;changed["extra"]=true
        XCTAssertThrowsError(try EEGTrialEvidence.recover(JSONSerialization.data(withJSONObject:changed)))
    }

}
