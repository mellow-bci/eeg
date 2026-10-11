import XCTest
@testable import EEGCore

final class ReferenceNumericalLeavesTests: XCTestCase {
    typealias N = ReferenceNumericalLeaves
    func testRecoveredWorkspacesAndResourceBounds() throws {
        XCTAssertEqual(try N.workspace(dimension: 2, method: .divideAndConquer, maximumDimension: 20), .init(doubles: 42, integers: 39))
        XCTAssertEqual(try N.workspace(dimension: 2, method: .standard, maximumDimension: 20), .init(doubles: 15, integers: 0))
        XCTAssertThrowsError(try N.workspace(dimension: 0, method: .standard, maximumDimension: 20))
        XCTAssertThrowsError(try N.workspace(dimension: 21, method: .standard, maximumDimension: 20))
    }
    func testBothLeavesPreserveNegativeRootsAndUpperTriangleContract() throws {
        for method in [N.Method.standard, .divideAndConquer] {
            let result = try N.eigenbasis(columnMajor: [-1e-14,99,0,2], dimension: 2, method: method, maximumDimension: 20)
            XCTAssertEqual(result.ascendingValues[0], -1e-14, accuracy: 1e-25)
            XCTAssertEqual(result.ascendingValues[1], 2, accuracy: 1e-12)
            XCTAssertEqual(result.attempts, [.init(method: method, info: 0)])
        }
    }
    func testRepeatedRootUsesSubspaceInvariantAndRejectsInvalidInputs() throws {
        let result = try N.eigenbasis(columnMajor: [3,0,0,3], dimension: 2, method: .divideAndConquer, maximumDimension: 20)
        let v = result.columnMajorVectors
        XCTAssertEqual(result.ascendingValues, [3,3])
        XCTAssertEqual(v[0]*v[0]+v[1]*v[1], 1, accuracy: 1e-12)
        XCTAssertEqual(v[0]*v[2]+v[1]*v[3], 0, accuracy: 1e-12)
        XCTAssertThrowsError(try N.eigenbasis(columnMajor: [1], dimension: 2, method: .standard, maximumDimension: 20))
        XCTAssertThrowsError(try N.eigenbasis(columnMajor: [.nan], dimension: 1, method: .standard, maximumDimension: 20))
    }
}
