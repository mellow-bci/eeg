import XCTest
@testable import EEGCore

final class ReferenceTypeSevenCQRecipeTests: XCTestCase {
    private func recipe() throws -> ReferenceTypeSevenCQRecipe.Recipe {
        try ReferenceTypeSevenCQRecipe.current(revision: 0x0740,
            configurationBytes: [1, 128, 0, 16, 32, 16], connectionType: 1)
    }
    func testCurrentOptionAndOrdinalCalibrationRecipe() throws {
        let result = try recipe()
        XCTAssertEqual(result.mode, 7)
        XCTAssertEqual(result.eegSampleRate, 128)
        XCTAssertEqual(result.eegResolution, 16)
        XCTAssertEqual(result.motionSampleRate, 32)
        XCTAssertEqual(result.motionResolution, 16)
        XCTAssertEqual(result.channels.map { $0.calibrationChannelID }, [45,51,40,43,54,64,69,77,82,92,103,106,95,101])
        XCTAssertEqual(result.channels.map { $0.rawEEGIndex }, [0,1,2,3,4,5,6,8,9,10,11,12,13,14])
        XCTAssertEqual(result.channels.map { $0.configuration.divisor }, [212,216,226,235,231,239,245,179,167,162,206,204,194,179])
        XCTAssertTrue(result.channels.allSatisfy { $0.configuration.offset == 0 && !$0.configuration.f68RangeGroup })
    }
    func testInitialRawAndConstructorStatesRemainDistinct() throws {
        let result = try recipe()
        XCTAssertEqual(result.initialRememberedRawValues, Array(repeating: 0, count: 14))
        XCTAssertEqual(result.initialStates, Array(repeating: 4, count: 14))
        let recalculated = try result.snapshot(rawValuesInCQOrdinalOrder: result.initialRememberedRawValues)
        XCTAssertEqual(recalculated.channels.map { $0.state }, Array(repeating: 0, count: 14))
        XCTAssertEqual(recalculated.overall, 0)
    }
    func testComposedCalibrationUsesQuarterScaleAndRevisionBranch() throws {
        let result = try recipe()
        let normalized = [0.1, 0.4, 1.5] + Array(repeating: 2.0, count: 11)
        let raw = zip(result.channels, normalized).map { Double($0.0.configuration.divisor) * $0.1 * 4 }
        let diagnostic = try result.snapshot(rawValuesInCQOrdinalOrder: raw)
        XCTAssertEqual(diagnostic.channels.map { $0.raw }, raw)
        XCTAssertEqual(diagnostic.channels.map { $0.state }, [0,1,2] + Array(repeating: 4, count: 11))
        XCTAssertEqual(diagnostic.overall, 25)
        for (channel, expected) in zip(diagnostic.channels, normalized) {
            XCTAssertEqual(channel.normalized, expected, accuracy: 1e-12)
        }
    }
    func testUnqualifiedConfigurationsAreRejected() {
        XCTAssertThrowsError(try ReferenceTypeSevenCQRecipe.current(revision: 0x0730,
            configurationBytes: [1,128,0,16,32,16], connectionType: 1))
        XCTAssertThrowsError(try ReferenceTypeSevenCQRecipe.current(revision: 0x0740,
            configurationBytes: [1,128,0,16,32,16], connectionType: 2))
        XCTAssertThrowsError(try ReferenceTypeSevenCQRecipe.current(revision: 0x0740,
            configurationBytes: [1,0,1,16,32,16], connectionType: 1))
    }
}
