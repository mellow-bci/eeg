import XCTest
import Foundation
@testable import EEGCore

final class TrialEvidenceTests: XCTestCase {
    private func trial() throws -> EEGTrialEvidence {
        try EEGTrialEvidence(id: "trial-1", sessionID: "session-1", participantID: "synthetic", condition: .silentSerialSubtraction, startingNumber: 613)
    }
    private func completeCues() throws -> EEGTrialEvidence {
        var value = try trial()
        try value.requestCue(at: 1, participantReady: true, audioCheckHeard: true, transportStable: true, recordingActive: true)
        try value.cueStarted(at: 1.1); try value.cueCompleted(at: 4)
        XCTAssertEqual(value.conditionDeadline, 24)
        try value.requestEndCue(at: 24); try value.endCueStarted(at: 24.1); try value.endCueCompleted(at: 25)
        return value
    }
    func testOnlyExplicitReviewedAttemptBecomesDatasetTrial() throws {
        var value = try completeCues()
        XCTAssertThrowsError(try value.datasetTrial())
        try value.report(.attempted, at: 26)
        XCTAssertFalse(value.accepted)
        XCTAssertThrowsError(try value.datasetTrial())
        try value.review(accept: true, reviewer: "operator", reason: "cue_acknowledged_and_participant_reported", at: 27)
        let row = try value.datasetTrial()
        XCTAssertEqual(row.start, 9); XCTAssertEqual(row.end, 21)
        XCTAssertEqual(row.label, "silent_serial_subtraction"); XCTAssertEqual(row.cue_completed_at, 4)
        XCTAssertEqual(value.observedBehavior, "unknown")
        let data = try JSONEncoder().encode(row)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(object["label_verified"] as? Bool, true)
        XCTAssertThrowsError(try value.interrupt(reason: "edit after review", at: 28))
    }
    func testReadinessTimingAndMissedCueCannotProduceAcceptedLabel() throws {
        var value = try trial()
        XCTAssertThrowsError(try value.requestCue(at: 1, participantReady: false, audioCheckHeard: true, transportStable: true, recordingActive: true))
        XCTAssertEqual(value.phase, .planned)
        XCTAssertThrowsError(try value.cueCompleted(at: 4))
        try value.requestCue(at: 1, participantReady: true, audioCheckHeard: true, transportStable: true, recordingActive: true)
        XCTAssertThrowsError(try value.cueStarted(at: .nan))
        try value.cueStarted(at: 2); try value.cueCompleted(at: 4)
        XCTAssertThrowsError(try value.requestEndCue(at: 23.99))
        try value.interrupt(reason: "transport lost", at: 10)
        XCTAssertThrowsError(try value.requestEndCue(at: 24))
        XCTAssertThrowsError(try value.datasetTrial())
        var missed = try completeCues()
        try missed.report(.missedCue, at: 26)
        XCTAssertThrowsError(try missed.review(accept: true, reviewer: "operator", reason: "guess", at: 27))
        try missed.review(accept: false, reviewer: "operator", reason: "missed cue", at: 27)
        XCTAssertThrowsError(try missed.datasetTrial())
    }
}
