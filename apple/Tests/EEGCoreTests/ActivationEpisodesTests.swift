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
}
