import XCTest
@testable import EEGCore

final class TrialAssociationEvidenceTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    private let classes = ["neutral", "silent_serial_subtraction"]
    private func recording(count: Int = 24, rejectedIndex: Int? = nil, withSamples: Bool = false) throws -> (EEGRecordingStore, URL, String, [EEGTrialTiming]) {
        let store = try EEGRecordingStore(directory: root), file = try store.start()
        let plan = try EEGTrialPlan(sessionID: "s", participantID: "p", seed: 42)
        try store.appendEvent(kind: "trial_plan", fields: ["json": String(decoding: try JSONEncoder().encode(plan), as: UTF8.self)])
        if withSamples {
            try store.appendEvent(kind: "device_metadata", fields: ["81072f44-9f3d-11e3-a9dc-0002a5d5c51b": "018000102010"])
            try store.appendEvent(kind: "transport_status", fields: ["status": "stable"])
        }
        var timings = [EEGTrialTiming]()
        for index in 0..<count {
            let at = Double(index) * 100 + 1
            var trial = plan.trials[index]
            try store.appendTrialEvidence(trial)
            try trial.requestCue(at: at, participantReady: true, audioCheckHeard: true, transportStable: true, recordingActive: true)
            try store.appendTrialEvidence(trial)
            try trial.cueStarted(at: at + 1); try store.appendTrialEvidence(trial)
            try trial.cueCompleted(at: at + 2); try store.appendTrialEvidence(trial)
            if withSamples {
                for offset in 0..<(6 * 256) {
                    let i = index * 6 * 256 + offset, t = at + 7 + Double(offset) / 128
                    let word = UInt16(31200 + Int(50 * sin(t * 2 * Double.pi * 10)))
                    try store.append(sample: EEGSample(index: i, counter: i % 128, receivedAt: t, continuous: offset > 0,
                        adcWords: Array(repeating: word, count: 15),
                        electrodesADC: Dictionary(uniqueKeysWithValues: EEGRecordingStore.channels.map { ($0, Double(word)) }),
                        electrodesMicrovolts: Dictionary(uniqueKeysWithValues: EEGRecordingStore.channels.map { ($0, Double(word) / 7.8) }),
                        notificationSlot: 0, recordFlag: 0))
                }
            }
            try trial.requestEndCue(at: at + 22); try store.appendTrialEvidence(trial)
            try trial.endCueStarted(at: at + 22.1); try store.appendTrialEvidence(trial)
            try trial.endCueCompleted(at: at + 24); try store.appendTrialEvidence(trial)
            try trial.report(.attempted, at: at + 25); try store.appendTrialEvidence(trial)
            try trial.review(accept: index != rejectedIndex, reviewer: "synthetic", reason: "fixture", at: at + 26)
            try store.appendTrialEvidence(trial)
            let label = trial.requestedCondition.rawValue
            var timing = EEGTrialTiming(sessionID: "s", trialID: trial.id, label: label,
                condition: label == "neutral" ? "cued_neutral" : "cued_task",
                start: at + 7, end: at + 19, cueCompletedAt: at + 2)
            timing.coveredSeconds = 12; timing.eligibleSeconds = 10
            timing.containedCandidateWindows = label == "neutral" ? 0 : 2
            timing.containedTargetWindows = timing.containedCandidateWindows
            timings.append(timing)
        }
        try store.finish()
        let recovered = try store.recoverTrialRecording(recording: file)
        XCTAssertEqual(recovered.plan.seed, plan.seed)
        XCTAssertEqual(recovered.plan.trials.map(\.id), plan.trials.map(\.id))
        return (store, file, recovered.fileSHA256, timings)
    }
    func testCanonicalRecordedEvaluationIncludesConditionalResultWithoutChangingInference() throws {
        let (store, file, _, _) = try recording(withSamples: true)
        let base = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: base.appendingPathComponent("Fixtures/spectrum/mental-training.json"))) as! [String: Any]
        var records = object["records"] as! [[String: Any]]
        for index in records.indices {
            records[index]["participant_id"] = "p"
            if records[index]["label"] as? String != "neutral" { records[index]["label"] = "silent_serial_subtraction" }
        }
        let profile = try EEGProfileCreation.train(JSONDecoder().decode([EEGTrainingRecord].self,
            from: JSONSerialization.data(withJSONObject: records)), participantID: "p").profile
        let manifest = try EEGTrialDatasetExport.manifest(sources: [.init(recording: file, split: .evaluation,
            independenceDeclaration: "Synthetic test only")], store: store)
        let baseline = try EEGEvaluationArtifact.run(manifest: manifest, store: store, profile: profile)
        let artifact = try EEGEvaluationArtifact.run(manifest: manifest, store: store, profile: profile,
            trialAssociationMinimumEligibleFraction: 0.8)
        let assessment = try XCTUnwrap(artifact.trialAssociation?["s"])
        let value = try XCTUnwrap(assessment.result, assessment.reason ?? "no reason")
        XCTAssertEqual(value.eligibleFractionsByTrialID.count, 24)
        XCTAssertEqual(value.association.admissibleSchedules, 705982)
        XCTAssertEqual(value.association.candidateObserved.count, 24)
        XCTAssertEqual(artifact.report.predictions.map(\.predictedLabel), baseline.report.predictions.map(\.predictedLabel))
        XCTAssertNil(baseline.trialAssociation)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: artifact.data) as? [String: Any])
        XCTAssertEqual(json["algorithm_version"] as? String, "native-labeled-evaluation-12")
        XCTAssertNotNil(json["trial_association"] as? [String: Any])
        XCTAssertFalse(artifact.report.systemControlEnabled)
        XCTAssertFalse(artifact.report.hardwareValidated)
        // Exercise an explicit unavailable outcome without inventing negative trials.
        let tooStrict = try EEGEvaluationArtifact.run(manifest: manifest, store: store, profile: profile,
            trialAssociationMinimumEligibleFraction: 1)
        XCTAssertEqual(tooStrict.trialAssociation?["s"]?.reason, "insufficientExposure")
        XCTAssertNil(tooStrict.trialAssociation?["s"]?.result)
    }
    func testCompletedJournalJoinsAllTrialsAndPreservesBytes() throws {
        let (store, file, hash, timings) = try recording()
        let before = try Data(contentsOf: file)
        let result = try EEGTrialPlanAssociation.run(recording: file, store: store, expectedFileSHA256: hash,
            participantID: "p", sessionID: "s", classes: classes, trials: timings.reversed(), minimumEligibleFraction: 0.8)
        XCTAssertEqual(result.sourceFileSHA256, hash)
        XCTAssertEqual(result.minimumEligibleFraction, 0.8)
        XCTAssertEqual(result.eligibleFractionsByTrialID.count, 24)
        XCTAssertTrue(result.eligibleFractionsByTrialID.values.allSatisfy { $0 == 10.0 / 12 })
        XCTAssertEqual(result.association.atLeastObservedSchedules, 1)
        XCTAssertEqual(try Data(contentsOf: file), before)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any])
        XCTAssertEqual(json["sourceFileSHA256"] as? String, hash)
        // This fixture has no EEG. It tests evidence joining, not computed detector outcomes.
    }
    func testMissingRejectedAndDuplicateTrialsCannotBecomeFalseOutcomes() throws {
        for count in [0, 23, 24] {
            let (store, file, hash, timings) = try recording(count: count, rejectedIndex: count == 24 ? 4 : nil)
            XCTAssertThrowsError(try EEGTrialPlanAssociation.run(recording: file, store: store, expectedFileSHA256: hash,
                participantID: "p", sessionID: "s", classes: classes, trials: timings, minimumEligibleFraction: 0.8))
        }
        let (store, file, hash, timings) = try recording()
        for rows in [Array(timings.dropLast()), Array(timings.dropLast()) + [timings[0]]] {
            XCTAssertThrowsError(try EEGTrialPlanAssociation.run(recording: file, store: store, expectedFileSHA256: hash,
                participantID: "p", sessionID: "s", classes: classes, trials: rows, minimumEligibleFraction: 0.8))
        }
    }
    func testSourceIdentityAndSingleTaskSemanticsAreRequired() throws {
        let (store, file, hash, timings) = try recording()
        for (h, p, s, c) in [("wrong", "p", "s", classes), (hash, "other", "s", classes),
                              (hash, "p", "other", classes), (hash, "p", "s", ["neutral", "task"]),
                              (hash, "p", "s", classes + ["another-task"])] {
            XCTAssertThrowsError(try EEGTrialPlanAssociation.run(recording: file, store: store, expectedFileSHA256: h,
                participantID: p, sessionID: s, classes: c, trials: timings, minimumEligibleFraction: 0.8))
        }
        var changed = timings
        let t = timings[0]
        changed[0] = EEGTrialTiming(sessionID: t.sessionID, trialID: t.trialID, label: t.label,
            condition: t.condition, start: t.start, end: t.end, cueCompletedAt: nil)
        XCTAssertThrowsError(try EEGTrialPlanAssociation.run(recording: file, store: store, expectedFileSHA256: hash,
            participantID: "p", sessionID: "s", classes: classes, trials: changed, minimumEligibleFraction: 0.8))
    }
    func testAssessmentDistinguishesMissingPlanFromSourceMismatch() throws {
        let (store, file, hash, timings) = try recording()
        func dataset(_ name: String, _ digest: String) -> EEGTrainingDataset {
            EEGTrainingDataset(evaluation: [], participantID: "p", records: [], sessions: [
                .init(id: "s", split: "evaluation", fileSHA256: digest, eegSHA256: "synthetic",
                    usableWindows: 0, rejectedWindows: 0, recordingName: name)])
        }
        let report = EEGLabeledEvaluation(minimumWindowsPerClass: 1, controlsOnly: false, profileID: "synthetic",
            predictions: [], metrics: EEGLabeledEvaluation.summarize([], classes: classes), trials: timings,
            conditions: [:], sessionConditions: [:])
        XCTAssertThrowsError(try EEGTrialPlanAssociation.assess(store: store,
            dataset: dataset(file.lastPathComponent, "different"), report: report, minimumEligibleFraction: 0.8)) { error in
            guard case EEGTrialPlanAssociation.EvidenceFailure.sourceMismatch = error else { return XCTFail("Unexpected: \(error)") }
        }
        let complete = try EEGTrialPlanAssociation.assess(store: store,
            dataset: dataset(file.lastPathComponent, hash), report: report, minimumEligibleFraction: 0.8)
        XCTAssertNotNil(complete["s"]?.result)
        let absent = try store.start(); try store.finish()
        let absentHash = try store.clockEvidence(recording: absent).fileSHA256
        let unavailable = try EEGTrialPlanAssociation.assess(store: store,
            dataset: dataset(absent.lastPathComponent, absentHash), report: report, minimumEligibleFraction: 0.8)
        XCTAssertEqual(unavailable["s"]?.reason, "missing_native_trial_plan")
        XCTAssertEqual(unavailable["s"]?.explanation, "No native trial plan was recorded.")
        XCTAssertNil(unavailable["s"]?.result)
        XCTAssertThrowsError(try EEGTrialPlanAssociation.assess(store: store,
            dataset: dataset(absent.lastPathComponent, "stale"), report: report, minimumEligibleFraction: 0.8))
        let malformed = try store.start()
        try store.appendEvent(kind: "trial_plan", fields: ["json": "{}"]); try store.finish()
        let malformedHash = try store.clockEvidence(recording: malformed).fileSHA256
        XCTAssertThrowsError(try EEGTrialPlanAssociation.assess(store: store,
            dataset: dataset(malformed.lastPathComponent, malformedHash), report: report, minimumEligibleFraction: 0.8))
    }
    func testExposureMustBeFiniteSufficientAndConsistent() throws {
        let (store, file, hash, timings) = try recording()
        for threshold in [0, -1, Double.nan, 1.1, 0.9] {
            XCTAssertThrowsError(try EEGTrialPlanAssociation.run(recording: file, store: store, expectedFileSHA256: hash,
                participantID: "p", sessionID: "s", classes: classes, trials: timings, minimumEligibleFraction: threshold))
        }
        for mode in 0..<6 {
            var changed = timings
            switch mode {
            case 0: changed[0].eligibleSeconds = .nan
            case 1: changed[0].coveredSeconds = 13
            case 2: changed[0].coveredSeconds = 9
            case 3: changed[0].eligibleSeconds = 0
            case 4: changed[0].containedCandidateWindows = -1
            default: changed[0].containedTargetWindows = changed[0].containedCandidateWindows + 1
            }
            XCTAssertThrowsError(try EEGTrialPlanAssociation.run(recording: file, store: store, expectedFileSHA256: hash,
                participantID: "p", sessionID: "s", classes: classes, trials: changed, minimumEligibleFraction: 0.8))
        }
    }
}
