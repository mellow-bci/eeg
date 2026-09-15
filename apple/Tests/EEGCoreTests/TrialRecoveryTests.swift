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
        try trial.requestEndCue(at:23);try trial.endCueStarted(at:23.1);try trial.endCueCompleted(at:25)
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
    func testPlanOrderAndRestAreRequiredDuringRecovery() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let plan=try EEGTrialPlan(sessionID:"session",participantID:"synthetic",seed:42)
        for mode in ["missing", "reordered", "short_rest", "valid"] {
            let store=try EEGRecordingStore(directory:root),file=try store.start()
            if mode != "missing" {
                try store.appendEvent(kind:"trial_plan",fields:["json":String(decoding:try JSONEncoder().encode(plan),as:UTF8.self)])
            }
            var first=plan.trials[mode == "reordered" ? 1 : 0]
            try store.appendTrialEvidence(first)
            try first.interrupt(reason:"synthetic_stop",at:2);try store.appendTrialEvidence(first)
            if mode == "short_rest" || mode == "valid" {
                var second=plan.trials[1];try store.appendTrialEvidence(second)
                try second.requestCue(at:mode == "valid" ? 12 : 11.9,participantReady:true,audioCheckHeard:true,transportStable:true,recordingActive:true)
                try store.appendTrialEvidence(second)
            }
            try store.finish()
            if mode == "valid" { XCTAssertEqual(try store.recoveredTrials(recording:file).count,2) }
            else { XCTAssertThrowsError(try store.recoveredTrials(recording:file)) }
        }
    }
    func testFractionalObservationTimesSurviveRecordingRecovery() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store=try EEGRecordingStore(directory:root)
        let plan=try EEGTrialPlan(sessionID:"session",participantID:"synthetic",seed:42)
        for i in 0..<100 {
            let file=try store.start()
            try store.appendEvent(kind:"trial_plan",fields:["json":String(decoding:try JSONEncoder().encode(plan),as:UTF8.self)])
            var trial=plan.trials[0]
            try store.appendTrialEvidence(trial)
            let at=(100000.123456789+Double(i)*0.000132)-100000.1
            try trial.requestCue(at:at,participantReady:true,audioCheckHeard:true,transportStable:true,recordingActive:true)
            try store.appendTrialEvidence(trial)
            try trial.cueStarted(at:at+1);try store.appendTrialEvidence(trial)
            try trial.cueCompleted(at:at+2);try store.appendTrialEvidence(trial)
            try trial.requestEndCue(at:at+22);try store.appendTrialEvidence(trial)
            try trial.endCueStarted(at:at+22.1);try store.appendTrialEvidence(trial)
            try trial.endCueCompleted(at:at+24);try store.appendTrialEvidence(trial)
            try trial.report(.attempted,at:at+25);try store.appendTrialEvidence(trial)
            try trial.review(accept:true,reviewer:"synthetic operator",reason:"fixture",at:at+26)
            try store.appendTrialEvidence(trial)
            try store.finish()
            let recovered=try XCTUnwrap(store.recoveredTrials(recording:file).first)
            XCTAssertEqual(recovered.events.map(\.at),trial.events.map(\.at))
            XCTAssertEqual(recovered.phase,.reviewed)
            XCTAssertEqual(try recovered.datasetTrial().start,try trial.datasetTrial().start)
        }
    }
    func testManualObservationSurvivesJournalWithoutChangingReportedCondition() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try EEGRecordingStore(directory: root), file = try store.start()
        let plan = try EEGTrialPlan(sessionID: "session", participantID: "synthetic", seed: 42)
        try store.appendEvent(kind: "trial_plan", fields: ["json": String(decoding: try JSONEncoder().encode(plan), as: UTF8.self)])
        var trial = plan.trials[0]
        try store.appendTrialEvidence(trial)
        func step(_ change: (inout EEGTrialEvidence) throws -> Void) throws {
            try change(&trial)
            try store.appendTrialEvidence(trial)
        }
        try step { try $0.requestCue(at: 1, participantReady: true, audioCheckHeard: true, transportStable: true, recordingActive: true) }
        try step { try $0.cueStarted(at: 2) }
        try step { try $0.cueCompleted(at: 3) }
        try step { try $0.requestEndCue(at: 23) }
        try step { try $0.endCueStarted(at: 23.1) }
        try step { try $0.endCueCompleted(at: 25) }
        let notes = "Observer: synthetic reviewer; direct observation\nApprox. 12.5 s: blink; head movement unknown. No sensor reference — timing uncertain."
        try step { try $0.report(.uncertain, at: 26, observedBehavior: notes) }
        let reported = trial
        XCTAssertThrowsError(try trial.review(accept: true, reviewer: "operator", reason: "Notes cannot override uncertainty", at: 27))
        var nextReview = trial
        try nextReview.review(accept: false, reviewer: "operator", reason: "Uncertain participant report", at: 27)
        var changedReview = try JSONSerialization.jsonObject(with: JSONEncoder().encode(nextReview)) as! [String: Any]
        changedReview["observedBehavior"] = "Rewritten before persistence"
        let rejectedRevision = try EEGTrialEvidence.recover(JSONSerialization.data(withJSONObject: changedReview))
        XCTAssertThrowsError(try store.appendTrialEvidence(rejectedRevision))
        // Rejecting the conflicting revision must not prevent saving the valid one.
        try step { try $0.review(accept: false, reviewer: "operator", reason: "Uncertain participant report", at: 27) }
        try store.finish()
        let recovered = try XCTUnwrap(store.recoveredTrials(recording: file).first)
        XCTAssertEqual(recovered.observedBehavior, notes)
        XCTAssertEqual(recovered.requestedCondition, plan.trials[0].requestedCondition)
        XCTAssertEqual(recovered.participantReport, .uncertain)
        XCTAssertEqual(recovered.events.first { $0.kind == "participant_report" }?.at, 26)
        XCTAssertFalse(recovered.accepted)
        XCTAssertThrowsError(try recovered.datasetTrial())
        // Each snapshot is structurally valid on its own; only the history can
        // detect a later revision rewriting an observation from the report.
        var lines = try String(contentsOf: file).split(separator: "\n").map(String.init)
        let index = try XCTUnwrap(lines.lastIndex { $0.contains("\"trial_evidence\"") })
        var event = try JSONSerialization.jsonObject(with: Data(lines[index].utf8)) as! [String: Any]
        var evidence = event["evidence"] as! [String: Any]
        evidence["observedBehavior"] = "Changed after reporting: no movement"
        let altered = try EEGTrialEvidence.recover(JSONSerialization.data(withJSONObject: evidence))
        XCTAssertThrowsError(try altered.validateRevision(after: reported))
        // The unchanged review and an unchanged interruption remain legal.
        XCTAssertNoThrow(try recovered.validateRevision(after: reported))
        var interrupted = reported
        try interrupted.interrupt(reason: "synthetic interruption", at: 27)
        XCTAssertNoThrow(try interrupted.validateRevision(after: reported))
        event["evidence"] = evidence
        lines[index] = String(decoding: try JSONSerialization.data(withJSONObject: event), as: UTF8.self)
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.recoveredTrials(recording: file))
    }
    func testSavedPlanMustMatchSeedExactly() throws {
        let plan=try EEGTrialPlan(sessionID:"session",participantID:"synthetic",seed:42)
        let data=try JSONEncoder().encode(plan)
        XCTAssertEqual(try EEGTrialPlan.recover(data).seed,"42")
        var object=try JSONSerialization.jsonObject(with:data) as! [String:Any]
        object["seed"]="43"
        XCTAssertThrowsError(try EEGTrialPlan.recover(JSONSerialization.data(withJSONObject:object)))
    }
    func testJournalRequiresFinalizationAndEveryRevision() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store=try EEGRecordingStore(directory:root),file=try store.start()
        let plan=try EEGTrialPlan(sessionID:"session",participantID:"synthetic",seed:42)
        try store.appendEvent(kind:"trial_plan",fields:["json":String(decoding:try JSONEncoder().encode(plan),as:UTF8.self)])
        var trial=plan.trials[0]
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
        lines.remove(at:3) // Remove cue-request revision, retaining final snapshot.
        try (lines.joined(separator:"\n")+"\n").write(to:file,atomically:true,encoding:.utf8)
        XCTAssertThrowsError(try store.recoveredTrials(recording:file))
    }
}
