import XCTest
@testable import EEGCore
final class ReferenceTrainingProfileUpdatesTests: XCTestCase {
    func testExistingCountsIncrementOnlyCurrentMappedColumn() throws {
        let counts = try ReferenceTrainingProfileUpdates.countTraining(action: 8, actionColumns: [1, 8, 4],
            existingCounts: [3, 5, 9], trainedActions: [], maximumActions: 8)
        XCTAssertEqual(counts, [3, 6, 9])
    }
    func testAbsentCountsAndAbsentTrainedPropertyStartsAtOne() throws {
        XCTAssertEqual(try ReferenceTrainingProfileUpdates.countTraining(action: 8, actionColumns: [1, 8, 4],
            existingCounts: nil, trainedActions: nil, maximumActions: 8), [0, 1, 0])
    }
    func testLegacyCountReconstructionKeepsUnlistedCurrentAtZero() throws {
        XCTAssertEqual(try ReferenceTrainingProfileUpdates.countTraining(action: 8, actionColumns: [1, 8, 4],
            existingCounts: nil, trainedActions: [1, 8], maximumActions: 8), [1, 2, 0])
        XCTAssertEqual(try ReferenceTrainingProfileUpdates.countTraining(action: 8, actionColumns: [1, 8, 4],
            existingCounts: nil, trainedActions: [1, 4], maximumActions: 8), [1, 0, 1])
        XCTAssertEqual(try ReferenceTrainingProfileUpdates.countTraining(action: 8, actionColumns: [1, 8, 4],
            existingCounts: nil, trainedActions: [], maximumActions: 8), [0, 0, 0])
    }
    func testAvailabilityReconciliationPreservesOldOrderThenAppendsNew() throws {
        XCTAssertEqual(try ReferenceTrainingProfileUpdates.updateTrainedActions(actionCatalogue: [1, 2, 4, 8],
            dataExists: [true, false, true, true], existingActions: [8, 2, 4], maximumActions: 8), [8, 4, 1])
        XCTAssertEqual(try ReferenceTrainingProfileUpdates.updateTrainedActions(actionCatalogue: [1, 2, 4],
            dataExists: [true, true, false], existingActions: [2, 2, 4], maximumActions: 8), [2, 2, 1])
        XCTAssertEqual(try ReferenceTrainingProfileUpdates.updateTrainedActions(actionCatalogue: [1, 2],
            dataExists: [false, false], existingActions: [1, 2], maximumActions: 8), [])
    }
    func testInvalidInputsAndExplicitBoundsFail() {
        XCTAssertThrowsError(try ReferenceTrainingProfileUpdates.countTraining(action: 3, actionColumns: [1, 2],
            existingCounts: nil, trainedActions: nil, maximumActions: 8))
        XCTAssertThrowsError(try ReferenceTrainingProfileUpdates.countTraining(action: 1, actionColumns: [1, 1],
            existingCounts: nil, trainedActions: nil, maximumActions: 8))
        for counts in [[Double.nan, 1], [-1, 1], [1], [Double.greatestFiniteMagnitude, 1]] {
            XCTAssertThrowsError(try ReferenceTrainingProfileUpdates.countTraining(action: 1, actionColumns: [1, 2],
                existingCounts: counts, trainedActions: nil, maximumActions: 8))
        }
        XCTAssertThrowsError(try ReferenceTrainingProfileUpdates.updateTrainedActions(actionCatalogue: [1, 2],
            dataExists: [true], existingActions: [], maximumActions: 8))
        XCTAssertThrowsError(try ReferenceTrainingProfileUpdates.updateTrainedActions(actionCatalogue: [1, 2],
            dataExists: [true, true], existingActions: [1, 1], maximumActions: 2))
    }
}
