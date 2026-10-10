import XCTest
@testable import EEGCore

final class ReferenceTrainingLifecycleTests: XCTestCase {
    private func state(delay: Float = 0, duration: Float = 2, minimum: Int = 2, maximum: Int = 2) throws -> ReferenceTrainingLifecycle {
        try .init(configuration: .init(samplingRate: 10, stepSamples: 10, startAfterSeconds: delay,
                                      trainingSeconds: duration, minimumEpochs: minimum, maximumEpochs: maximum))
    }
    private func advance(_ state: inout ReferenceTrainingLifecycle, control: Int = 1, valid: Bool = true,
                         now: Int64 = 0, primary: [[Double]] = [[1]],
                         fit: ([ReferenceNeutralTraining.Epoch], Int) -> ReferenceNeutralTraining.FitResult = { _, _ in XCTFail("unexpected fit"); return .saveFailed }) throws -> ReferenceTrainingLifecycle.Transition {
        try state.advance(control: control, action: 2, activeActionCount: 1, actionPreviouslyTrained: true,
                          scoringHistory: [-1, 0, 1, 2], valid: valid, primary: primary, secondary: [], nowMilliseconds: now,
                          fit: fit, resetAction: { _ in XCTFail("unexpected reset"); return .saveFailed })
    }
    func testCollectionWaitAcceptanceDoesNotMaskSaveFailure() throws {
        var s = try state()
        let first = try advance(&s)
        XCTAssertEqual(first.event, 1); XCTAssertTrue(first.appended); XCTAssertTrue(first.incrementTrainingAttempts)
        XCTAssertTrue(try advance(&s, now: 100).appended)
        let waiting = try advance(&s, now: 200)
        XCTAssertEqual(waiting.event, 2); XCTAssertFalse(waiting.completed); XCTAssertTrue(waiting.unlockTrainingControlOnly)
        XCTAssertEqual(waiting.thresholdAndScore?.0, 0.75); XCTAssertEqual(waiting.thresholdAndScore?.1, 0.5)
        XCTAssertNil(try advance(&s, now: 300).event)
        var fitCalls = 0
        let accepted = try advance(&s, control: 2, now: 400, fit: { epochs, action in
            fitCalls += 1; XCTAssertEqual(epochs.count, 2); XCTAssertEqual(action, 2); return .saveFailed
        })
        XCTAssertEqual(fitCalls, 1); XCTAssertEqual(accepted.event, 4)
        XCTAssertEqual(accepted.fitResult, .saveFailed); XCTAssertFalse(s.active)
        XCTAssertNil(s.timerOriginMilliseconds); XCTAssertEqual(s.epochs.count, 2)
    }
    func testInvalidEpochAdvancesSampleClockButIsNotStored() throws {
        var s = try state()
        _ = try advance(&s, valid: false)
        XCTAssertEqual(s.samples, 10); XCTAssertTrue(s.epochs.isEmpty)
        _ = try advance(&s, valid: false)
        let failed = try advance(&s)
        XCTAssertEqual(failed.event, 3); XCTAssertTrue(failed.completed); XCTAssertTrue(failed.unlockSettings)
        let rejectedAccept = try advance(&s, control: 2)
        XCTAssertEqual(rejectedAccept.event, 7); XCTAssertTrue(s.active)
        XCTAssertNotNil(s.timerOriginMilliseconds)
    }
    func testDelayAndWholeSecondWallLimit() throws {
        var s = try state(delay: 1)
        XCTAssertFalse(try advance(&s).appended) // strict > delay
        XCTAssertTrue(try advance(&s, now: 3500, primary: []).appended == false)
        // Whole-second clock3500ms ->3 sec, belowfloat cap3.5.
        XCTAssertNil(try advance(&s, now: 3999, primary: []).event)
        let end = try advance(&s, now: 4000, primary: [])
        XCTAssertEqual(end.event, 3)
    }
    func testRollingPairedBufferAndRejection() throws {
        var s = try state(duration: 10)
        _ = try advance(&s, primary: [[1]])
        _ = try advance(&s, primary: [[2]])
        let third = try advance(&s, primary: [[3]])
        XCTAssertTrue(third.droppedOldest); XCTAssertEqual(s.epochs.map(\.primary), [[[2]], [[3]]])
        XCTAssertEqual(try advance(&s, control: 3).event, 6)
        XCTAssertEqual(s.epochs.count, 2)
        s.resetState(); XCTAssertTrue(s.epochs.isEmpty); XCTAssertEqual(s.samples, 0)
        XCTAssertEqual(try advance(&s).event, 1)
    }
    func testClockAndMalformedInputRejectedBeforeMutation() throws {
        var s = try state()
        _ = try advance(&s, now: 1000)
        XCTAssertThrowsError(try advance(&s, now: 999))
        XCTAssertThrowsError(try advance(&s, now: 1001, primary: [[1], [1, 2]]))
        XCTAssertEqual(s.samples, 10); XCTAssertEqual(s.epochs.count, 1)
    }
    func testResetDelegatesAndReportsBuildFailureSeparately() throws {
        var s = try state()
        let result = try s.advance(control: 4, action: 2, activeActionCount: 2, actionPreviouslyTrained: false,
                                  scoringHistory: [], valid: true, primary: [], secondary: [], nowMilliseconds: 0,
                                  fit: { _, _ in XCTFail(); return .saveFailed }, resetAction: { action in
            XCTAssertEqual(action, 2); return .buildFailed(emptyBankSaved: false)
        })
        XCTAssertEqual(result.event, 5); XCTAssertEqual(result.fitResult, .buildFailed(emptyBankSaved: false))
        XCTAssertEqual(result.thresholdAndScore?.0 ?? 0, 2.0 / 3.0, accuracy: 1e-15)
    }
    func testAcceptedEpochsProduceActualBankStatistics() throws {
        var lifecycle = try ReferenceTrainingLifecycle(configuration: .init(samplingRate: 1, stepSamples: 1,
            startAfterSeconds: 0, trainingSeconds: 20, minimumEpochs: 20, maximumEpochs: 20))
        for i in 0..<20 {
            _ = try advance(&lifecycle, now: Int64(i * 10), primary: [[Double(i)], [Double(i * 2)]])
        }
        var bank: [ReferenceTrainingBank.ClassEntry] = []
        let accepted = try advance(&lifecycle, control: 2, now: 300, fit: { epochs, action in
            do {
                let features = try ReferenceTrainingEpochAssembly.combineColumns(epochs.map(\.primary), maximumCells: 40)
                bank = try ReferenceTrainingBank.addUpdate(featureRows: features, updateTimes: [123.9],
                    classReferenceID: Int32(action), bank: bank, maximumEpochs: 20, maximumClasses: 2,
                    maximumDistributionsPerClass: 1)
                // This test validates training statistics only. No classifier
                // persistence is attempted, so it explicitly reports save failure.
                return .saveFailed
            } catch { XCTFail("unexpected statistics failure: \(error)"); return .buildFailed(emptyBankSaved: false) }
        })
        XCTAssertEqual(accepted.event, 4); XCTAssertEqual(accepted.fitResult, .saveFailed)
        XCTAssertEqual(bank.count, 1)
        XCTAssertEqual(bank[0].distributions[0].mean, [9.5, 19])
        XCTAssertEqual(bank[0].distributions[0].counts, [20, 20])
        XCTAssertEqual(bank[0].distributions[0].covariance[0][0], 35, accuracy: 1e-12)
        XCTAssertEqual(bank[0].distributions[0].updateTime, 123)
    }

    func testAcceptancePersistenceOrderingAndFailure() {
        for buildSucceeded in [true, false] {
            var calls: [String] = []
            let outcome = ReferenceTrainingPersistence.accept(build: { calls.append("build"); return buildSucceeded },
                clearClassifier: { calls.append("clear") }, save: { calls.append("save"); return false },
                clearErrors: { calls.append("errors") }, updateTrainingCount: { calls.append("count") },
                updateActions: { calls.append("actions") }, updateBrainMapIfEligible: { calls.append("brain") },
                unlockSettings: { calls.append("unlock") })
            XCTAssertEqual(outcome, buildSucceeded ? .saveFailed : .buildFailed(emptyBankSaved: false))
            XCTAssertEqual(calls, (buildSucceeded ? ["build", "save"] : ["build", "clear", "save"]) +
                ["errors", "count", "actions", "brain", "unlock"])
        }
    }

    func testColumnAssemblyOrderShapeAndBound() throws {
        let matrices = [[[1.0, 2], [10, 20]], [[3], [30]], [[], []]]
        XCTAssertEqual(try ReferenceTrainingEpochAssembly.combineColumns(matrices, maximumCells: 6), [[1, 2, 3], [10, 20, 30]])
        XCTAssertThrowsError(try ReferenceTrainingEpochAssembly.combineColumns(matrices, maximumCells: 5))
        XCTAssertThrowsError(try ReferenceTrainingEpochAssembly.combineColumns([[[1]], [[2], [3]]], maximumCells: 10))
        XCTAssertEqual(try ReferenceTrainingEpochAssembly.combineColumns([], maximumCells: 10), [])
    }

}
