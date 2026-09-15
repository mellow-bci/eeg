import XCTest
@testable import EEGCore

final class TrialPlanTests: XCTestCase {
    func testSeedReplayBalanceAndRunLimit() throws {
        let encoder = JSONEncoder();encoder.outputFormatting = [.sortedKeys]
        for seed in [UInt64(0),1,42,999,.max] {
            let plan = try EEGTrialPlan(sessionID: "session",participantID: "synthetic",seed:seed)
            XCTAssertEqual(try encoder.encode(plan),try encoder.encode(EEGTrialPlan(sessionID:"session",participantID:"synthetic",seed:seed)))
            XCTAssertEqual(plan.trials.count,24)
            XCTAssertEqual(plan.trials.filter { $0.requestedCondition == .neutral }.count,12)
            XCTAssertEqual(Set(plan.trials.map(\.id)).count,24)
            XCTAssertTrue(plan.trials.allSatisfy { (100...999).contains($0.startingNumber) && $0.phase == .planned })
            for i in 3..<24 { XCTAssertFalse((1...3).allSatisfy { plan.trials[i].requestedCondition == plan.trials[i-$0].requestedCondition }) }
        }
    }
    func testControlPlanRecoversAndKeepsConditionsSeparate() throws {
        for seed in [UInt64(0),42,999] {
            let plan = try EEGTrialPlan(sessionID:"controls",participantID:"synthetic",seed:seed,controls:true)
            XCTAssertEqual(plan.trials.count,24)
            XCTAssertEqual(plan.controlProtocol,"eeg.artifact-controls.v1")
            for condition in [EEGTrialEvidence.Condition.ordinaryActivity,.blinkControl,.jawControl,.headMovementControl] {
                XCTAssertEqual(plan.trials.filter { $0.requestedCondition == condition }.count,6)
            }
            let recovered = try EEGTrialPlan.recover(JSONEncoder().encode(plan))
            XCTAssertEqual(recovered.trials.map(\.requestedCondition),plan.trials.map(\.requestedCondition))
            XCTAssertTrue(recovered.trials.allSatisfy { $0.isControl && $0.protocolID == "eeg.artifact-controls.v1" })
        }
    }
    func testEnforcesTerminalEvidenceRestBlocksAndCompletion() throws {
        let plan = try EEGTrialPlan(sessionID:"session",participantID:"synthetic",seed:42)
        XCTAssertEqual(try plan.next(after:nil,started:0,at:0).id,plan.trials[0].id)
        for started in [1,8,16,23] {
            var previous=plan.trials[started-1]
            XCTAssertThrowsError(try plan.next(after:previous,started:started,at:500))
            try previous.interrupt(reason:"synthetic_stop",at:100)
            let rest: Double = started % 8 == 0 ? 60 : 10
            XCTAssertThrowsError(try plan.next(after:previous,started:started,at:100+rest-0.001))
            XCTAssertEqual(try plan.next(after:previous,started:started,at:100+rest).id,plan.trials[started].id)
        }
        XCTAssertThrowsError(try plan.next(after:nil,started:24,at:1000))
        XCTAssertThrowsError(try plan.next(after:nil,started:0,at:.nan))
        XCTAssertThrowsError(try EEGTrialPlan(sessionID:" ",participantID:"synthetic",seed:1))
    }
}
