import XCTest
@testable import EEGCore

final class ReferenceNeutralTrainingTests: XCTestCase {
    private func collect(_ state: inout ReferenceNeutralTraining, valid: Bool = true,
                         primary: [[Double]] = [[1]], secondary: [[Double]] = []) throws -> ReferenceNeutralTraining.Transition {
        try state.advance(autoSampling: 1, trainingControl: 0, valid: valid,
                          primary: primary, secondary: secondary) { _, _ in XCTFail("fit during collection"); return .saveFailed }
    }
    func testPairedEpochsAndRepeatedLock() throws {
        var state = try ReferenceNeutralTraining(minimumEpochs: 2, maximumBufferedEpochs: 4)
        XCTAssertTrue(try collect(&state).lockSettings)
        XCTAssertTrue(try collect(&state, primary: [[2, 3]], secondary: [[4]]).lockSettings)
        XCTAssertEqual(state.epochs.count, 2)
        XCTAssertEqual(state.epochs[0].secondary, [])
        var fits = 0
        let result = try state.advance(autoSampling: 0, trainingControl: 0, valid: false, primary: [], secondary: []) { epochs, action in
            fits += 1; XCTAssertEqual(epochs.count, 2); XCTAssertEqual(action, 1); return .saved
        }
        XCTAssertEqual(fits, 1)
        XCTAssertEqual(result.completion, .fitted(.saved))
        XCTAssertEqual(result.event, 8)
        XCTAssertTrue(result.unlockSettings)
        XCTAssertTrue(result.clearClassifierErrorsAndUpdateActions)
        XCTAssertFalse(state.collecting)
        XCTAssertTrue(state.epochs.isEmpty)
    }
    func testInvalidAndEmptyDoNotAppendButStartCollection() throws {
        var state = try ReferenceNeutralTraining(minimumEpochs: 2, maximumBufferedEpochs: 4)
        XCTAssertFalse(try collect(&state, valid: false).appended)
        XCTAssertFalse(try collect(&state, primary: []).appended)
        XCTAssertTrue(state.collecting)
        let result = try state.advance(autoSampling: 0, trainingControl: 0, valid: true, primary: [], secondary: []) { _, _ in
            XCTFail("insufficient epochs must not fit"); return .saved
        }
        XCTAssertEqual(result.completion, .insufficientEpochs(collected: 0, required: 2))
        XCTAssertEqual(result.event, 8)
        XCTAssertNil(result.trainingAction)
        XCTAssertFalse(result.clearClassifierErrorsAndUpdateActions)
    }
    func testTrainingControlOneStopsActiveAutosampling() throws {
        var state = try ReferenceNeutralTraining(minimumEpochs: 1, maximumBufferedEpochs: 2)
        _ = try collect(&state)
        let result = try state.advance(autoSampling: 1, trainingControl: 1, valid: true, primary: [[2]], secondary: []) { epochs, _ in
            XCTAssertEqual(epochs.count, 1); return .saveFailed
        }
        XCTAssertEqual(result.completion, .fitted(.saveFailed))
        XCTAssertEqual(result.autoSamplingValue, 0)
    }
    func testBuildFailureIsNotSaveFailure() throws {
        var state = try ReferenceNeutralTraining(minimumEpochs: 1, maximumBufferedEpochs: 1)
        _ = try collect(&state)
        let result = try state.advance(autoSampling: 0, trainingControl: 0, valid: false, primary: [], secondary: []) { _, _ in
            .buildFailed(emptyBankSaved: false)
        }
        XCTAssertEqual(result.completion, .fitted(.buildFailed(emptyBankSaved: false)))
        XCTAssertTrue(result.unlockSettings)
        XCTAssertTrue(state.epochs.isEmpty)
    }
    func testCapacityAndBadMatrixDoNotMutateState() throws {
        var state = try ReferenceNeutralTraining(minimumEpochs: 1, maximumBufferedEpochs: 1)
        XCTAssertThrowsError(try collect(&state, primary: [[.nan]]))
        XCTAssertFalse(state.collecting)
        _ = try collect(&state)
        XCTAssertThrowsError(try collect(&state)) { XCTAssertEqual($0 as? ReferenceNeutralTraining.InputError, .bufferCapacity) }
        XCTAssertEqual(state.epochs.count, 1)
        let reset = state.reset()
        XCTAssertEqual(reset.autoSampling, 0); XCTAssertEqual(reset.action, 1); XCTAssertEqual(reset.control, 0)
        XCTAssertFalse(state.collecting); XCTAssertTrue(state.epochs.isEmpty)
        XCTAssertTrue(try collect(&state).appended)
    }
    func testUnsupportedControlAndInactiveStop() throws {
        var state = try ReferenceNeutralTraining(minimumEpochs: 1, maximumBufferedEpochs: 1)
        XCTAssertThrowsError(try state.advance(autoSampling: 2, trainingControl: 0, valid: true, primary: [], secondary: []) { _, _ in .saved })
        let result = try state.advance(autoSampling: 0, trainingControl: 0, valid: true, primary: [], secondary: []) { _, _ in XCTFail(); return .saved }
        XCTAssertEqual(result, .init())
    }
}
