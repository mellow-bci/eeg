import XCTest
@testable import EEGCore

final class ReferenceCommandScoringTests: XCTestCase {
    func testProfileActivationMappingAndNeutralRows() throws {
        for (setting, expected) in [(0, 0.55), (7, 0.0)] {
            let scorer = try ReferenceCommandScoring(actions: [2], activationSetting: setting)
            XCTAssertEqual(scorer.activationThreshold, expected, accuracy: 1e-15)
        }
        var scorer = try ReferenceCommandScoring(actions: [2, 8], activationSetting: 7)
        XCTAssertEqual(try scorer.process(filteredProbabilities: [0.8, 0.1, 0.05, 0.05]).action, 1)
        XCTAssertEqual(try scorer.process(filteredProbabilities: [0.05, 0.1, 0.05, 0.8]).action, 1)
        let command = try scorer.process(filteredProbabilities: [0.05, 0.1, 0.8, 0.05])
        XCTAssertEqual(command.action, 8)
        XCTAssertEqual(command.power, 0.7, accuracy: 1e-15)
    }

    func testActivationHysteresisAndZeroReset() throws {
        var scorer = try ReferenceCommandScoring(actions: [2], activationSetting: 7)
        XCTAssertEqual(try scorer.process(filteredProbabilities: [0.3, 0.5, 0.2]).power, 0)
        XCTAssertFalse(scorer.isActivated)
        XCTAssertEqual(try scorer.process(filteredProbabilities: [0.2, 0.7, 0.1]).power, 0.5, accuracy: 1e-15)
        XCTAssertTrue(scorer.isActivated)
        XCTAssertEqual(try scorer.process(filteredProbabilities: [0.3, 0.5, 0.2]).power, 0.2, accuracy: 1e-15)
        XCTAssertEqual(try scorer.process(filteredProbabilities: [0.5, 0.3, 0.2]).power, 0)
        XCTAssertFalse(scorer.isActivated)
        XCTAssertEqual(try scorer.process(filteredProbabilities: [0.3, 0.5, 0.2]).power, 0)
    }

    func testMarginThresholdGateAndTies() throws {
        var scorer = try ReferenceCommandScoring(actions: [2, 4], activationSetting: 0)
        XCTAssertEqual(try scorer.process(filteredProbabilities: [0.1, 0.4, 0.4, 0.1]).power, 0)
        let out = try scorer.process(filteredProbabilities: [0.05, 0.9, 0.03, 0.02])
        XCTAssertEqual(out.action, 2)
        XCTAssertEqual(out.power, (0.85 - 0.55) / 0.45, accuracy: 1e-15)
        var zero = try ReferenceCommandScoring(actions: [2], activationSetting: 7)
        XCTAssertEqual(try zero.process(filteredProbabilities: [0.45, 0.45, 0.1]).power, 0)
    }

    func testInvalidInputClearsLatchAndRequiresNewActivation() throws {
        var scorer = try ReferenceCommandScoring(actions: [2], activationSetting: 7)
        _ = try scorer.process(filteredProbabilities: [0.05, 0.9, 0.05])
        XCTAssertThrowsError(try scorer.process(filteredProbabilities: [.nan, 0.9, 0.05]))
        XCTAssertFalse(scorer.isActivated)
        XCTAssertEqual(try scorer.process(filteredProbabilities: [0.3, 0.5, 0.2]).power, 0)
        XCTAssertThrowsError(try scorer.process(filteredProbabilities: [0, 1]))
        XCTAssertThrowsError(try scorer.process(filteredProbabilities: [0, 1.1, 0]))
        XCTAssertThrowsError(try ReferenceCommandScoring(actions: [1], activationSetting: 7))
        XCTAssertThrowsError(try ReferenceCommandScoring(actions: [2, 2], activationSetting: 7))
        XCTAssertThrowsError(try ReferenceCommandScoring(actions: [2], activationSetting: 8))
    }
}
