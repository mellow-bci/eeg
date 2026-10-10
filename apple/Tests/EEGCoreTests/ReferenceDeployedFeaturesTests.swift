import XCTest
@testable import EEGCore

final class ReferenceDeployedFeaturesTests: XCTestCase {
    func testOrderedPowerAndRatioUseDecibelsWithoutFlattening() throws {
        let a = ReferenceDeployedFeatures.Coordinate(row: 1, band: 0)
        let b = ReferenceDeployedFeatures.Coordinate(row: 0, band: 1)
        let result = try ReferenceDeployedFeatures.extract(channelBands: [[2, 10], [100, 4]],
            features: [.power(a), .ratio(numerator: a, denominator: b), .power(a)])
        XCTAssertEqual(result, [20, 10, 20])
        XCTAssertThrowsError(try ReferenceDeployedFeatures.extract(channelBands: [[0]],
            features: [.power(.init(row: 0, band: 0))]))
    }
    func testComputeGateIncludesTrainingWithoutClassifier() {
        for empty in [false, true] {
            for active in [false, true] {
                for control in [0, 1, 2, 3, 4, 5] {
                    XCTAssertEqual(ReferenceDeployedFeatures.shouldComputeFeatures(classifierEmpty: empty,
                        trainingActive: active, trainingControl: control, epochEmpty: false),
                        !empty || active || control == 1)
                    XCTAssertFalse(ReferenceDeployedFeatures.shouldComputeFeatures(classifierEmpty: empty,
                        trainingActive: active, trainingControl: control, epochEmpty: true))
                }
            }
        }
    }
    func testOverallContactBoundaryIsFiftyInVendorUnits() {
        XCTAssertFalse(ReferenceDeployedFeatures.overallContactIsClean(49.999))
        XCTAssertTrue(ReferenceDeployedFeatures.overallContactIsClean(50))
        XCTAssertFalse(ReferenceDeployedFeatures.overallContactIsClean(.nan))
    }
    func testBackgroundFirstOutputZeroAndCountSaturates() throws {
        var background = ReferenceTrainingBackground()
        XCTAssertEqual(try background.process([2, 4]), [0, 0])
        XCTAssertEqual(try background.process([4, 8]), [1, 2])
        for _ in 2..<480 { _ = try background.process([3, 6]) }
        XCTAssertEqual(background.count, 480)
        let previous = background.mean
        let output = try background.process([483, 966])
        XCTAssertEqual(background.count, 480)
        XCTAssertEqual(background.mean[0], (479 * previous[0] + 483) / 480, accuracy: 1e-12)
        XCTAssertEqual(output[0], 483 - background.mean[0], accuracy: 1e-12)
        let saved = background.mean
        XCTAssertThrowsError(try background.process([1]))
        XCTAssertEqual(background.mean, saved)
        XCTAssertEqual(try background.process([]), [])
        background.reset(); XCTAssertEqual(background.count, 0)
    }
}
