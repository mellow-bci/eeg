import XCTest
@testable import EEGCore

final class ReferenceEEGInterpolationTests: XCTestCase {
    typealias I = ReferenceEEGInterpolation
    func testSpatialBasisCoefficientsPreserveOriginalsAndChannelOrder() throws {
        // Basis vectors isolate every recovered coefficient without reusing implementation math.
        let ids = [40, 54, 72, 92, 106]
        let rows = (0..<5).map { i in (0..<5).map { $0 == i ? 1.0 : 0.0 } }
        let result = try I.spatialInsight(rows: rows, channelIDs: ids, randomDraws: nil, maximumRows: 5)
        XCTAssertEqual(result.measuredRows, rows)
        XCTAssertEqual(result.combinedChannelIDs, ids + [45,101,64,82,51,95,43,103,77,69])
        let source54 = [0.134,0.0254,0.4453,0.0166,0.2374,0.0126,0.0424,-0.01,-0.047,0]
        let source40 = [0.2921,-0.144,0.077,0.0587,0.2925,0.0428,0.2076,0.1287,0.055,0]
        for j in 0..<10 {
            XCTAssertEqual(result.synthesizedRows[0][j], source40[j], accuracy: 1e-14)
            XCTAssertEqual(result.synthesizedRows[1][j], source54[j], accuracy: 1e-14)
        }
        XCTAssertEqual(result.synthesizedRows[2][9], 1)
        XCTAssertEqual(result.combinedRows[0].prefix(5), rows[0][...])
    }
    func testExplicitRandomDrawOrderAndPartitionDeterminism() throws {
        let row = [1.0,2,3,4,5]
        let draws: [UInt64] = [0,UInt64.max,1 << 63,0,1 << 63,UInt64.max,0,0,0,UInt64.max]
        let base = try I.spatialInsight(rows: [row], channelIDs: I.sourceIDs, randomDraws: nil, maximumRows: 1)
        let whole = try I.spatialInsight(rows: [row,row], channelIDs: I.sourceIDs, randomDraws: draws+draws, maximumRows: 2)
        let part = try I.spatialInsight(rows: [row], channelIDs: I.sourceIDs, randomDraws: draws, maximumRows: 1)
        XCTAssertEqual(whole.synthesizedRows, part.synthesizedRows + part.synthesizedRows)
        XCTAssertEqual(I.randomMultiplier(draw: 0), 0.999)
        XCTAssertEqual(I.randomMultiplier(draw: 1 << 63), 1)
        XCTAssertEqual(I.randomMultiplier(draw: UInt64.max), 1.001, accuracy: 1e-15)
        XCTAssertEqual(part.synthesizedRows[0][0], base.synthesizedRows[0][0] * 0.999)
        XCTAssertEqual(part.synthesizedRows[0][9], 3 * I.randomMultiplier(draw: UInt64.max))
    }
    func testGapKernelAndCounterBoundaries() throws {
        XCTAssertEqual(try I.gapValues(previous: [0,10], current: [8,2], missing: 3), [[2,8],[4,6],[6,4]])
        XCTAssertEqual(try I.gapValues(previous: [1], current: [2], missing: 0), [])
        XCTAssertEqual(try I.missingCount(previousCounter: 127, currentCounter: 2, maximumCounter: 127), 2)
        XCTAssertEqual(try I.missingCount(previousCounter: 0, currentCounter: 65, maximumCounter: 127), 64)
        XCTAssertNil(try I.missingCount(previousCounter: 0, currentCounter: 66, maximumCounter: 127))
        XCTAssertNil(try I.missingCount(previousCounter: 2, currentCounter: 2, maximumCounter: 127))
    }
    func testMalformedInputsFailRatherThanProduceMeasurementSuccess() throws {
        XCTAssertThrowsError(try I.spatialInsight(rows: [[1,2,3,4,5]], channelIDs: I.sourceIDs, randomDraws: [], maximumRows: 1))
        XCTAssertThrowsError(try I.spatialInsight(rows: [[1,2,3,4,5]], channelIDs: I.sourceIDs, randomDraws: nil, maximumRows: 0))
        XCTAssertThrowsError(try I.spatialInsight(rows: [[1,2,3,4,.nan]], channelIDs: I.sourceIDs, randomDraws: nil, maximumRows: 1))
        XCTAssertThrowsError(try I.spatialInsight(rows: [], channelIDs: [1,2,3,4,5], randomDraws: nil, maximumRows: 1))
        XCTAssertThrowsError(try I.gapValues(previous: [1], current: [2], missing: 65))
        XCTAssertThrowsError(try I.gapValues(previous: [-Double.greatestFiniteMagnitude], current: [Double.greatestFiniteMagnitude], missing: 1))
    }
}
