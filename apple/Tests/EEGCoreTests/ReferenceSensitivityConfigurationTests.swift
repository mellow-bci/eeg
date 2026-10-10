import XCTest
@testable import EEGCore

final class ReferenceSensitivityConfigurationTests: XCTestCase {
    func testHeadsetNormalizationAndAbsentVersion() {
        XCTAssertEqual((0...9).map { ReferenceSensitivityConfiguration.normalizedHeadsetType(Int32($0)) },
                       [0,1,1,4,4,5,5,4,4,9])
        XCTAssertEqual(ReferenceSensitivityConfiguration.normalizedHeadsetType(-1), -1)
        XCTAssertEqual(ReferenceSensitivityConfiguration.version(headsetType: 8, entries: [:]), "notFound")
    }

    func testINIWholeMapPrecedenceAndNormalizationCollisionOrder() throws {
        let json = ReferenceSensitivityConfiguration.JSONEntry(headsetType: 1, version: "test", values: [99])
        let entries = try ReferenceSensitivityConfiguration.resolve(parsedINI: [3:[3], 8:[8]], orderedJSON: [json])
        XCTAssertEqual(entries, [4:.init(version: "configIniFile", values: [8])])
        XCTAssertEqual(ReferenceSensitivityConfiguration.managerMap(entries), [4:[8]])
        XCTAssertEqual(ReferenceSensitivityConfiguration.version(headsetType: 7, entries: entries), "configIniFile")
    }

    func testJSONRejectsEmptyVersionAndDefaultsNonNumbersToZero() throws {
        let entries = try ReferenceSensitivityConfiguration.resolve(parsedINI: [:], orderedJSON: [
            .init(headsetType: 2, version: "", values: [9]),
            .init(headsetType: 8, version: "first", values: [1,nil,3]),
            .init(headsetType: 3, version: "last", values: [])
        ])
        XCTAssertEqual(entries, [4:.init(version: "last", values: [])])
        let converted = try ReferenceSensitivityConfiguration.resolve(parsedINI: [:], orderedJSON: [
            .init(headsetType: 8, version: "fixture", values: [1,nil,3])])
        XCTAssertEqual(converted[4]?.values, [1,0,3])
    }

    func testSetterDoesNotReselectAndMissingHeadsetUsesExistingFallback() throws {
        var state = ReferenceSensitivityConfiguration.ManagerState()
        let table = (1...10).map { Double($0) * 2 }
        try state.set([4:table])
        state.select(headsetType: 8)
        XCTAssertEqual(try state.classWeights(activeActionCount: 2, thresholdSlots: [1,10,5,5]), [1,2,20])
        try state.set([4:Array(repeating: 7, count: 10)])
        XCTAssertEqual(state.selectedValues, table)
        try state.set([:])
        XCTAssertEqual(state.map[4], Array(repeating: 7, count: 10))
        state.select(headsetType: 99)
        XCTAssertEqual(state.selectedValues, [])
        XCTAssertEqual(try state.classWeights(activeActionCount: 1, thresholdSlots: [5,5,5,5]), [1,1])
    }

    func testActionThresholdBoundaryAndFinitePolicy() throws {
        XCTAssertEqual(try ReferenceSensitivityConfiguration.validateActionThresholds([1,10,5,2]), [1,10,5,2])
        for values: [Int32] in [[1,2,3], [0,2,3,4], [1,2,3,11]] {
            XCTAssertThrowsError(try ReferenceSensitivityConfiguration.validateActionThresholds(values))
        }
        var state = ReferenceSensitivityConfiguration.ManagerState()
        try state.set([4:[1]])
        XCTAssertThrowsError(try state.set([4:[.nan]]))
        XCTAssertEqual(state.map, [4:[1]])
        XCTAssertThrowsError(try ReferenceSensitivityConfiguration.resolve(parsedINI: [4:[.infinity]], orderedJSON: []))
    }
}
