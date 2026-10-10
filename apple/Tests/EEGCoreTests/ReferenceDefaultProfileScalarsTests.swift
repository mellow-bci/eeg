import XCTest
@testable import EEGCore

final class ReferenceDefaultProfileScalarsTests: XCTestCase {
    typealias S = ReferenceDefaultProfileScalars
    func testTrainingDefaultCompositionRequiresExplicitTimingAndRealAcceptance() throws {
        let config = S.trainingConfiguration(samplingRate: 128,stepSamples: 16)
        XCTAssertEqual(config.startAfterSeconds,1)
        XCTAssertEqual(config.trainingSeconds,8)
        XCTAssertEqual(config.minimumEpochs,12)
        XCTAssertEqual(config.maximumEpochs,100)
        var lifecycle = try ReferenceTrainingLifecycle(configuration: config)
        let outcome = try lifecycle.advance(control: 2,action: 1,activeActionCount: 0,
            actionPreviouslyTrained: false,scoringHistory: [],valid: true,primary: [],secondary: [],
            nowMilliseconds: 0,fit: { _,_ in XCTFail("Insufficient epochs must not fit"); return .buildFailed(emptyBankSaved: false) },
            resetAction: { _ in XCTFail("Accept must not reset"); return .buildFailed(emptyBankSaved: false) })
        XCTAssertEqual(outcome.event,7)
        XCTAssertNil(outcome.fitResult)
        XCTAssertThrowsError(try ReferenceTrainingLifecycle(configuration:
            S.trainingConfiguration(samplingRate: 0,stepSamples: 16)))
    }
    func testEmptyTrainingStateAndActionVocabularyAreNotTrainedAssets() throws {
        XCTAssertEqual(S.actionIDs,(0..<14).map { UInt32(1) << $0 })
        XCTAssertEqual(S.zeroMatrices["cognitiv-brainMapCoords"]?.rows,14)
        XCTAssertEqual(S.zeroMatrices["cognitiv-brainMapCoords"]?.columns,2)
        XCTAssertEqual(S.zeroMatrices["cognitiv-actionSkillHistory"]?.rows,3)
        XCTAssertEqual(S.zeroMatrices["cognitiv-actionSkillHistory"]?.columns,14)
        for matrix in S.zeroMatrices.values {
            XCTAssertEqual(matrix.elements.count,matrix.rows * matrix.columns)
            XCTAssertTrue(matrix.elements.allSatisfy { $0 == 0 })
            XCTAssertEqual(try matrix.rowValues().count,matrix.rows)
        }
        XCTAssertEqual(S.emptyMatrixKeys,["cognitiv-activeActions","cognitiv-trainedActions"])
    }
    func testThresholdNoiseCacheAndNeutralAssignmentsPreserveTypes() {
        XCTAssertEqual(S.values["cognitiv-activationThreshold"],.integer(4))
        for action in 1...4 { XCTAssertEqual(S.values["cognitiv-action\(action)Threshold"],.integer(5)) }
        XCTAssertEqual(S.values["cognitiv-actionStability"],.floating(0.5))
        XCTAssertEqual(S.values["cognitiv-honeyLevel"],.floating(Double(bitPattern: 0x3f847ae147ae147b)))
        XCTAssertEqual(S.values["cognitiv-maxNumOfNoisyChannels"],.integer(4))
        XCTAssertEqual(S.values["cognitiv-enableErrorSetClassifiers"],.integer(0))
        XCTAssertEqual(S.values["cognitiv-maxErrorSetClassifiers"],.integer(20))
        XCTAssertEqual(S.values["cognitiv-enableCachedClassifiers"],.integer(1))
        XCTAssertEqual(S.values["cognitiv-maxCachedClassifiers"],.integer(20))
        XCTAssertEqual(S.values["cognitiv-autoSamplingNeutral"],.integer(0))
        XCTAssertEqual(S.values["cognitiv-trainingAcceptThreshold"],.floating(0))
        // Absence is not permission to invent a default.
        XCTAssertNil(S.values["cognitiv-neutralScale"])
        XCTAssertNil(S.values["cognitiv-sensitivity"])
        XCTAssertNil(S.values["cognitiv-priors"])
        XCTAssertNil(S.values["cognitiv-backgroundEnabled"])
    }
}
