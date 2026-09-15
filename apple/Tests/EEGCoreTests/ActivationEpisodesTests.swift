import XCTest
@testable import EEGCore

final class ActivationEpisodesTests: XCTestCase {
    private func row(_ start: Double, session: String = "session", trial: String = "a", trialStart: Double = 0, usable: Bool = true, armed: Bool = true) -> EEGTrainingDataset.EvaluationWindow {
        .init(input: EEGInferenceWindow(values: [], feature_config_id: "test", artifact_flags: [], usable: usable,
            participant_id: "test", session_id: session, continuity_id: "segment", window_id: String(start), start: start, end: start + 2),
            label: "neutral", trialID: trial, condition: "ordinary_activity", shadowEnabled: armed, trialStart: trialStart, trialEnd: 20, cueCompletedAt: nil)
    }
    private func candidate(_ evidence: Double) -> EEGExperimentalProposal {
        .init(profileID: "test", windowID: "test", reason: "profile_not_hardware_validated", experimentalCandidate: "task", evidenceStart: evidence, uncalibratedScores: nil)
    }
    func testRepeatedCandidateAndTrialCarryDoNotBecomeFreshOnsets() throws {
        var counter = EEGActivationEpisodes()
        try counter.consume(row(0), proposal: candidate(0))
        try counter.consume(row(2), proposal: candidate(0))
        try counter.consume(row(4, trial: "b", trialStart: 4), proposal: candidate(0))
        let result = counter.conditions["ordinary_activity"]!
        XCTAssertEqual(result.candidateWindows, 3)
        XCTAssertEqual(result.episodeOnsets, 1)
        XCTAssertEqual(result.carryInCandidates, 1)
        XCTAssertNil(result.episodeOnsetsPerHour)
    }
    func testRejectedAndUnarmedExposureIsSeparateAndResetsEpisode() throws {
        var counter = EEGActivationEpisodes()
        try counter.consume(row(0), proposal: candidate(0))
        try counter.consume(row(2, usable: false), proposal: nil)
        try counter.consume(row(4, armed: false), proposal: nil)
        try counter.consume(row(6), proposal: candidate(6))
        let result = counter.conditions["ordinary_activity"]!
        XCTAssertEqual(result.eligibleSeconds, 4)
        XCTAssertEqual(result.rejectedSeconds, 2)
        XCTAssertEqual(result.unarmedSeconds, 2)
        XCTAssertEqual(result.episodeOnsets, 2)
        XCTAssertEqual(result.episodeOnsetsPerHour, 1800)
    }
    func testSessionRatesDoNotHideDifferentActivityOrCarryIns() throws {
        var counter = EEGActivationEpisodes()
        try counter.consume(row(0, session:"quiet"), proposal:nil)
        try counter.consume(row(2, session:"quiet"), proposal:nil)
        try counter.consume(row(4, session:"quiet", usable:false), proposal:nil)
        try counter.consume(row(0, session:"active"), proposal:candidate(0))
        try counter.consume(row(2, session:"active"), proposal:candidate(0))
        try counter.consume(row(4, session:"active", trial:"b", trialStart:4), proposal:candidate(0))
        let quiet = try XCTUnwrap(counter.sessionConditions["quiet"]?["ordinary_activity"])
        let active = try XCTUnwrap(counter.sessionConditions["active"]?["ordinary_activity"])
        XCTAssertEqual(quiet.eligibleSeconds,4)
        XCTAssertEqual(quiet.rejectedSeconds,2)
        XCTAssertEqual(quiet.episodeOnsets,0)
        XCTAssertEqual(quiet.episodeOnsetsPerHour,0)
        XCTAssertNotNil(quiet.poissonUpper95PerHour)
        XCTAssertEqual(active.eligibleSeconds,6)
        XCTAssertEqual(active.episodeOnsets,1)
        XCTAssertEqual(active.carryInCandidates,1)
        XCTAssertNil(active.episodeOnsetsPerHour)
        XCTAssertNil(active.poissonUpper95PerHour)
        XCTAssertEqual(counter.conditions["ordinary_activity"]?.eligibleSeconds,10)
        XCTAssertEqual(counter.conditions["ordinary_activity"]?.candidateWindows,3)
        XCTAssertNil(counter.conditions["ordinary_activity"]?.episodeOnsetsPerHour)
    }
    func testInvalidEvidenceChronologyRejected() {
        var counter = EEGActivationEpisodes()
        XCTAssertThrowsError(try counter.consume(row(0), proposal: candidate(2)))
    }
    private func task(_ start: Double, cue: Double?) -> EEGTrainingDataset.EvaluationWindow {
        let base = row(start)
        return .init(input: base.input, label: "task", trialID: "task-trial", condition: "cued_task",
                     shadowEnabled: true, trialStart: 0, trialEnd: 20, cueCompletedAt: cue)
    }
    func testPreCueEvidenceDoesNotReceiveCueLatencyCredit() throws {
        var counter = EEGActivationEpisodes()
        try counter.consume(task(0, cue: 1), proposal: candidate(0))
        try counter.consume(task(2, cue: 1), proposal: candidate(0))
        XCTAssertNil(counter.trials[0].firstCueAssociatedCandidateLatency)
        XCTAssertEqual(counter.trials[0].cuedTargetDetected, false)
        try counter.consume(task(4, cue: 1), proposal: nil)
        try counter.consume(task(6, cue: 1), proposal: candidate(6))
        XCTAssertEqual(counter.trials[0].firstCueAssociatedCandidateLatency, 7)
        XCTAssertEqual(counter.trials[0].cuedTargetDetected, true)
        XCTAssertEqual(counter.trials[0].unobservedSeconds, 12)
    }
    func testMissingCueAndConflictingTrialMetadata() throws {
        var counter = EEGActivationEpisodes()
        try counter.consume(task(0, cue: nil), proposal: candidate(0))
        XCTAssertNil(counter.trials[0].firstCueAssociatedCandidateLatency)
        XCTAssertNil(counter.trials[0].cuedTargetDetected)
        XCTAssertThrowsError(try counter.consume(task(2, cue: 1), proposal: candidate(0)))
    }

    func testOtherTaskLabelDoesNotEarnTargetCredit() throws {
        var counter = EEGActivationEpisodes()
        let other = EEGExperimentalProposal(profileID: "test", windowID: "test",
            reason: "profile_not_hardware_validated", experimentalCandidate: "other-task",
            evidenceStart: 0, uncalibratedScores: nil)
        try counter.consume(task(0, cue: 0), proposal: other)
        XCTAssertEqual(counter.trials[0].scoredTargetDetected, false)
        XCTAssertEqual(counter.trials[0].containedCandidateWindows, 1)
        try counter.consume(task(2, cue: 0), proposal: candidate(2))
        XCTAssertEqual(counter.trials[0].scoredTargetDetected, true)
        XCTAssertEqual(counter.trials[0].containedTargetWindows, 1)
        XCTAssertEqual(counter.trials[0].eligibleFraction, 0.2, accuracy: 1e-12)
        XCTAssertNil(counter.trials[0].scoredNeutralFalsePositive)
    }
    func testNeutralTrialFalsePositiveExcludesCarryInAndUnusableEvidence() throws {
        func neutral(_ start: Double, usable: Bool = true, armed: Bool = true) -> EEGTrainingDataset.EvaluationWindow {
            let base = row(start, trialStart: 4, usable: usable, armed: armed)
            return .init(input: base.input, label: "neutral", trialID: "neutral-trial", condition: "cued_neutral",
                         shadowEnabled: armed, trialStart: 4, trialEnd: 20, cueCompletedAt: 1)
        }
        var counter = EEGActivationEpisodes()
        try counter.consume(neutral(4), proposal: candidate(2))
        XCTAssertEqual(counter.trials[0].scoredNeutralFalsePositive, false)
        try counter.consume(neutral(6, usable: false), proposal: candidate(6))
        try counter.consume(neutral(8, armed: false), proposal: candidate(8))
        XCTAssertEqual(counter.trials[0].containedCandidateWindows, 0)
        try counter.consume(neutral(10), proposal: candidate(10))
        XCTAssertEqual(counter.trials[0].scoredNeutralFalsePositive, true)
        XCTAssertEqual(counter.trials[0].containedTargetWindows, 0)
        XCTAssertEqual(counter.trials[0].eligibleFraction, 0.25, accuracy: 1e-12)
        XCTAssertEqual(counter.trials[0].unobservedSeconds, 8)
        XCTAssertNil(counter.trials[0].scoredTargetDetected)
    }
    func testMissingCueNeverBecomesScoredSuccess() throws {
        var counter = EEGActivationEpisodes()
        try counter.consume(task(0, cue: nil), proposal: candidate(0))
        XCTAssertEqual(counter.trials[0].containedTargetWindows, 1)
        XCTAssertNil(counter.trials[0].scoredTargetDetected)
    }

}
