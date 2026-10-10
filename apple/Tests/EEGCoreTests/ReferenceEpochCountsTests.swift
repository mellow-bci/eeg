import XCTest
@testable import EEGCore

final class ReferenceEpochCountsTests: XCTestCase {
    func testExtractionUsesCartesianIndicesWithDuplicates() throws {
        let selected = try ReferenceEpochCounts.extractGreaterThan([[6, 1, 8], [2, 9, 0]], threshold: 5, maximumCartesianCells: 100)
        XCTAssertEqual(selected.rowIndices, [0, 0, 1])
        XCTAssertEqual(selected.columnIndices, [0, 2, 1])
        XCTAssertEqual(selected.values, [[6, 8, 1], [6, 8, 1], [2, 0, 9]])
        // Cross-selected entries can be <=5: this is not a qualifying-value list.
        XCTAssertTrue(selected.values.flatMap { $0 }.contains(0))
    }

    func testSingleRowProjectionUsesFirstQualifyingCount() throws {
        XCTAssertEqual(try ReferenceEpochCounts.projectedCounts([[5, 8, 6, 20]], outputDimension: 3), [8, 8, 8])
        XCTAssertEqual(try ReferenceEpochCounts.projectedCounts([[30, 5, 10]], outputDimension: 2), [30, 30])
        let extracted = try ReferenceEpochCounts.extractGreaterThan([[5, 8, 6]], threshold: 5, maximumCartesianCells: 100)
        XCTAssertEqual(extracted.values, [[8, 6], [8, 6]])
    }

    func testMultirowProjectionAveragesFirstSelectedColumnAcrossRepeatedRows() throws {
        let output = try ReferenceEpochCounts.projectedCounts([[6, 1, 8], [2, 9, 0]], outputDimension: 2)
        XCTAssertEqual(output[0], 14.0 / 3, accuracy: 1e-14)
        XCTAssertEqual(output[1], 14.0 / 3, accuracy: 1e-14)
        // It can be below the qualification threshold because Cartesian extraction
        // includes cross cells. Do not replace with min/sum/global-average policy.
        XCTAssertLessThan(output[0], 5)
    }

    func testEmptyExtractionAndInvalidDataAreExplicit() throws {
        XCTAssertEqual(try ReferenceEpochCounts.extractGreaterThan([[1, 5]], threshold: 5, maximumCartesianCells: 100).values, [])
        XCTAssertEqual(try ReferenceEpochCounts.extractGreaterThan([], threshold: 5, maximumCartesianCells: 100).values, [])
        XCTAssertThrowsError(try ReferenceEpochCounts.projectedCounts([[1, 5]], outputDimension: 2)) {
            XCTAssertEqual($0 as? ReferenceEpochCounts.CountError, .noQualifyingCounts)
        }
        XCTAssertThrowsError(try ReferenceEpochCounts.projectedCounts([[8]], outputDimension: 0))
        XCTAssertThrowsError(try ReferenceEpochCounts.extractGreaterThan([[8], [9, 10]], threshold: 5, maximumCartesianCells: 100))
        XCTAssertThrowsError(try ReferenceEpochCounts.extractGreaterThan([[.nan]], threshold: 5, maximumCartesianCells: 100))
        XCTAssertThrowsError(try ReferenceEpochCounts.extractGreaterThan([[-1]], threshold: 5, maximumCartesianCells: 100))
        XCTAssertThrowsError(try ReferenceEpochCounts.extractGreaterThan([[8]], threshold: .infinity, maximumCartesianCells: 100))
        XCTAssertThrowsError(try ReferenceEpochCounts.projectedCounts(
            [[Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude]], outputDimension: 1))
    }

    func testExplicitCartesianCapacityAndDirectReductionAvoidQuadraticTemporary() throws {
        let counts = [[6.0, 8, 9]]
        XCTAssertThrowsError(try ReferenceEpochCounts.extractGreaterThan(counts, threshold: 5,
                                                                         maximumCartesianCells: 8)) {
            XCTAssertEqual($0 as? ReferenceEpochCounts.CountError, .capacityExceeded)
        }
        XCTAssertEqual(try ReferenceEpochCounts.extractGreaterThan(counts, threshold: 5,
                                                                   maximumCartesianCells: 9).values.count, 3)
        XCTAssertThrowsError(try ReferenceEpochCounts.extractGreaterThan(counts, threshold: 5,
                                                                         maximumCartesianCells: -1))
        let many = [Array(repeating: 8.0, count: 10_000)]
        XCTAssertThrowsError(try ReferenceEpochCounts.extractGreaterThan(many, threshold: 5,
                                                                         maximumCartesianCells: 1_000))
        // Mathematical equivalent consumes 10,000 repeated first-column values,
        // without allocating the 100,000,000-cell Cartesian matrix.
        XCTAssertEqual(try ReferenceEpochCounts.projectedCounts(many, outputDimension: 2), [8, 8])
    }
}
