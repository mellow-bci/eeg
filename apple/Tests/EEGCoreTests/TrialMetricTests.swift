import XCTest
@testable import EEGCore

final class TrialMetricTests: XCTestCase {
    private func trial(_ id: String, session: String = "A", label: String = "task", cue: Double? = 0,
                       eligible: Double = 12, candidate: Bool = false, condition: String? = nil) -> EEGTrialTiming {
        var value = EEGTrialTiming(sessionID: session, trialID: id, label: label,
            condition: condition ?? (label == "neutral" ? "cued_neutral" : "cued_task"),
            start: 5, end: 17, cueCompletedAt: cue)
        value.eligibleSeconds = eligible
        value.coveredSeconds = 12
        value.containedCandidateWindows = candidate ? 3 : 0
        value.containedTargetWindows = label != "neutral" && candidate ? 3 : 0
        return value
    }
    func testWholeTrialCountsKeepMissingCuesAndUnusableTrialsVisible() throws {
        let trials = [trial("positive", candidate: true), trial("negative"),
                      trial("missing", cue: nil, candidate: true), trial("unusable", eligible: 0),
                      trial("fp", label: "neutral", candidate: true), trial("quiet", label: "neutral"),
                      trial("blink", label: "neutral", candidate: true, condition: "blink_control")]
        let result = EEGLabeledEvaluation.summarizeTrials(trials, classes: ["task", "neutral", "absent"])
        let task = try XCTUnwrap(result["task"])
        XCTAssertEqual(task.declaredTrials, 4)
        XCTAssertEqual(task.scoredTrials, 3)
        XCTAssertEqual(task.observedTrials, 1) // Three windows are still one trial.
        XCTAssertEqual(task.noCandidateObservedTrials, 2)
        XCTAssertEqual(task.unavailableTrials, 1)
        XCTAssertEqual(task.trialsWithoutEligibleExposure, 1)
        XCTAssertEqual(task.observationFraction, 1.0 / 3)
        XCTAssertEqual(task.declaredSeconds, 48)
        XCTAssertEqual(task.eligibleSeconds, 36)
        XCTAssertEqual(task.eligibleFraction, 0.75)
        XCTAssertEqual(result["neutral"]?.declaredTrials, 2) // Artifact controls remain separate.
        XCTAssertEqual(result["neutral"]?.observationFraction, 0.5)
        XCTAssertEqual(result["absent"]?.declaredTrials, 0)
        XCTAssertNil(result["absent"]?.observationFraction)
        XCTAssertNil(result["absent"]?.eligibleFraction)
    }
    func testSessionsCannotBeReplacedByPooledRates() throws {
        let trials = [trial("1", candidate: true), trial("2", candidate: true),
                      trial("1", session: "B"), trial("2", session: "B", cue: nil)]
        let report = EEGLabeledEvaluation(minimumWindowsPerClass: 10, controlsOnly: false, profileID: "test", predictions: [],
            metrics: EEGLabeledEvaluation.summarize([], classes: ["task"]), trials: trials,
            conditions: [:], sessionConditions: [:])
        let summary = report.trialMetrics, sessions = report.sessionTrialMetrics
        XCTAssertEqual(summary["task"]?.observationFraction, 2.0 / 3)
        XCTAssertEqual(sessions["A"]?["task"]?.observationFraction, 1)
        XCTAssertEqual(sessions["B"]?["task"]?.observationFraction, 0)
        XCTAssertEqual(sessions["B"]?["task"]?.unavailableTrials, 1)
    }
    func testAllUnavailableDoesNotBecomeZeroPercent() throws {
        let result = EEGLabeledEvaluation.summarizeTrials([trial("1", cue: nil)], classes: ["task"])
        XCTAssertEqual(result["task"]?.declaredTrials, 1)
        XCTAssertEqual(result["task"]?.scoredTrials, 0)
        XCTAssertNil(result["task"]?.observationFraction)
    }
}
