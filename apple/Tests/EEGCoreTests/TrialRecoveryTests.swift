import XCTest
@testable import EEGCore

final class TrialRecoveryTests: XCTestCase {
    private func planned() throws -> EEGTrialEvidence {
        try EEGTrialEvidence(id:"trial",sessionID:"session",participantID:"synthetic",condition:.neutral,startingNumber:431)
    }
    func testRoundTripAndTamperedAcceptanceRejected() throws {
        var trial=try planned()
        let encoder=JSONEncoder()
        XCTAssertEqual(try EEGTrialEvidence.recover(encoder.encode(trial)).phase,.planned)
        try trial.requestCue(at:1,participantReady:true,audioCheckHeard:true,transportStable:true,recordingActive:true)
        try trial.cueStarted(at:2);try trial.cueCompleted(at:3)
        try trial.requestEndCue(at:23);try trial.endCueStarted(at:24);try trial.endCueCompleted(at:25)
        try trial.report(.attempted,at:26);try trial.review(accept:true,reviewer:"operator",reason:"reported condition",at:27)
        XCTAssertEqual(try EEGTrialEvidence.recover(encoder.encode(trial)).datasetTrial().start,8)
        var object=try JSONSerialization.jsonObject(with:encoder.encode(trial)) as! [String:Any]
        object["cueCompletedAt"]=4
        XCTAssertThrowsError(try EEGTrialEvidence.recover(JSONSerialization.data(withJSONObject:object)))
        object=try JSONSerialization.jsonObject(with:encoder.encode(planned())) as! [String:Any]
        object["accepted"]=true;object["phase"]="reviewed"
        XCTAssertThrowsError(try EEGTrialEvidence.recover(JSONSerialization.data(withJSONObject:object)))
        object=try JSONSerialization.jsonObject(with:encoder.encode(trial)) as! [String:Any]
        object["accepted"]=1 // Numeric truthiness must not substitute for a JSON Boolean.
        XCTAssertThrowsError(try EEGTrialEvidence.recover(JSONSerialization.data(withJSONObject:object)))
    }
    func testJournalRequiresFinalizationAndEveryRevision() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store=try EEGRecordingStore(directory:root),file=try store.start()
        var trial=try planned()
        try store.appendTrialEvidence(trial)
        try trial.requestCue(at:1,participantReady:true,audioCheckHeard:true,transportStable:true,recordingActive:true)
        try store.appendTrialEvidence(trial)
        try trial.interrupt(reason:"operator_stop",at:2);try store.appendTrialEvidence(trial)
        XCTAssertThrowsError(try store.recoveredTrials(recording:file))
        try store.finish()
        let recovered=try store.recoveredTrials(recording:file)
        XCTAssertEqual(recovered.count,1);XCTAssertEqual(recovered[0].phase,.interrupted)
        XCTAssertThrowsError(try recovered[0].datasetTrial())
        var lines=try String(contentsOf:file).split(separator:"\n").map(String.init)
        lines.remove(at:2) // Remove cue-request revision, retaining final snapshot.
        try (lines.joined(separator:"\n")+"\n").write(to:file,atomically:true,encoding:.utf8)
        XCTAssertThrowsError(try store.recoveredTrials(recording:file))
    }
}
