import XCTest
@testable import EEGCore

final class ActivationEpisodesTests: XCTestCase {
    private func row(_ start: Double, trial: String = "a", trialStart: Double = 0, usable: Bool = true, armed: Bool = true) -> EEGTrainingDataset.EvaluationWindow {
        .init(input: EEGInferenceWindow(values: [], feature_config_id: "test", artifact_flags: [], usable: usable,
            participant_id: "test", session_id: "session", continuity_id: "segment", window_id: String(start), start: start, end: start + 2),
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

}
