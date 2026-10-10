import XCTest
@testable import EEGCore

final class ReferenceContactQualityMappingTests: XCTestCase {
    func testResolutionScalingIsExplicitAndExcludesTypeFive() throws {
        XCTAssertEqual(try ReferenceContactQualityMapping.mappedValue(5480, eeg16Bit: true, headsetType: 7), 1370)
        XCTAssertEqual(try ReferenceContactQualityMapping.mappedValue(5480, eeg16Bit: false, headsetType: 7), 5480)
        XCTAssertEqual(try ReferenceContactQualityMapping.mappedValue(5480, eeg16Bit: true, headsetType: 5), 5480)
    }
    func testThresholdEqualityAdvancesAndRangeBranchChangesThirdState() throws {
        let thresholds = [0.2, 0.7, 1.3, 1.7]
        for (value, expected) in [(0.19, 0), (0.2, 1), (0.7, 2), (1.3, 3), (1.7, 4)] {
            XCTAssertEqual(try ReferenceContactQualityMapping.state(mappedValue: value, offset: 0, divisor: 1, thresholds: thresholds, f68RangeGroup: true), expected)
        }
        XCTAssertEqual(try ReferenceContactQualityMapping.state(mappedValue: 1.5, offset: 0, divisor: 1, thresholds: thresholds, f68RangeGroup: false), 2)
        XCTAssertEqual(try ReferenceContactQualityMapping.state(mappedValue: 23, offset: 20, divisor: 2, thresholds: thresholds, f68RangeGroup: true), 3)
    }
    func testOverallUsesWorstThreeRatherThanAllChannels() throws {
        XCTAssertEqual(try ReferenceContactQualityMapping.overall(states: [4, 4, 0, 1, 2, 4], maximumChannels: 14), 25)
        XCTAssertEqual(try ReferenceContactQualityMapping.overall(states: [4, 2], maximumChannels: 14), 75)
        XCTAssertEqual(try ReferenceContactQualityMapping.overall(states: [], maximumChannels: 14), 0)
        XCTAssertEqual(try ReferenceContactQualityMapping.overall(states: [4, 4, 4, 4], maximumChannels: 14), 100)
    }
    func testRejectsNonfiniteInvalidClassesAndUnresolvedConfiguration() {
        XCTAssertThrowsError(try ReferenceContactQualityMapping.mappedValue(.nan, eeg16Bit: true, headsetType: 7))
        XCTAssertThrowsError(try ReferenceContactQualityMapping.state(mappedValue: 1, offset: 0, divisor: 0, thresholds: [0.2, 0.7, 1.3, 1.7], f68RangeGroup: true))
        XCTAssertThrowsError(try ReferenceContactQualityMapping.state(mappedValue: 1, offset: 0, divisor: 1, thresholds: [1, 0, 2, 3], f68RangeGroup: true))
        XCTAssertThrowsError(try ReferenceContactQualityMapping.overall(states: [5], maximumChannels: 14))
        XCTAssertThrowsError(try ReferenceContactQualityMapping.overall(states: [4, 4], maximumChannels: 1))
    }
    func testComposedFourteenChannelSnapshotPreservesMeasurements() throws {
        // Explicit analytic calibration, not recovered EPOC X calibration assets.
        let configuration = ReferenceContactQualityMapping.ChannelConfiguration(
            offset: 10, divisor: 100, thresholds: [0.2, 0.7, 1.3, 1.7], f68RangeGroup: true)
        let raw = [40.0, 120, 320] + Array(repeating: 840.0, count: 11)
        let result = try ReferenceContactQualityMapping.snapshot(rawValues: raw,
            configurations: Array(repeating: configuration, count: 14),
            eeg16Bit: ReferenceContactQualityMapping.typeSevenUses16Bit(mode: 4),
            headsetType: 7, maximumChannels: 14)
        XCTAssertEqual(result.channels.map { $0.raw }, raw)
        XCTAssertEqual(result.channels[0].mapped, 10)
        XCTAssertEqual(result.channels[1].normalized, 0.2, accuracy: 1e-12)
        XCTAssertEqual(result.channels.map { $0.state }, [0, 1, 2] + Array(repeating: 4, count: 11))
        XCTAssertEqual(result.overall, 25)
        XCTAssertTrue(ReferenceContactQualityMapping.typeSevenUses16Bit(mode: 7))
        XCTAssertFalse(ReferenceContactQualityMapping.typeSevenUses16Bit(mode: 1))
        XCTAssertThrowsError(try ReferenceContactQualityMapping.snapshot(rawValues: raw,
            configurations: [configuration], eeg16Bit: true, headsetType: 7, maximumChannels: 14))
    }

}
