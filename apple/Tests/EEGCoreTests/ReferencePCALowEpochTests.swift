import XCTest
@testable import EEGCore

final class ReferencePCALowEpochTests: XCTestCase {
    private let basis = [[1.0,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]]
    private let roots = [4.0,3,2,1]

    func testFirstFeatureControlsInclusiveClippingNotMinimumCount() throws {
        let value = try ReferencePCALowEpoch.apply(counts: [4,2,3,4],
            descendingEigenvalues: roots, basis: basis)
        XCTAssertTrue(value.wasClipped)
        XCTAssertEqual(value.scratchCounts, [3,1,2,3])
        XCTAssertEqual(value.eigenvalues, [4,3,2])
        XCTAssertEqual(value.basis, [[1,0,0],[0,1,0],[0,0,1],[0,0,0]])
        let reordered = try ReferencePCALowEpoch.apply(counts: [2,4,3,4],
            descendingEigenvalues: roots, basis: basis)
        XCTAssertEqual(reordered.retainedCount, 1)
    }

    func testAnyCountAboveDimensionBypassesClipping() throws {
        let value = try ReferencePCALowEpoch.apply(counts: [2,5,3,4],
            descendingEigenvalues: roots, basis: basis)
        XCTAssertFalse(value.wasClipped)
        XCTAssertEqual(value.scratchCounts, [1,4,2,3])
        XCTAssertEqual(value.eigenvalues, roots)
        XCTAssertEqual(value.basis, basis)
    }

    func testFiniteFractionalEndpointTruncatesTowardZero() throws {
        let value = try ReferencePCALowEpoch.apply(counts: [3.75,2,3,4],
            descendingEigenvalues: roots, basis: basis)
        XCTAssertEqual(value.retainedCount, 2)
        XCTAssertEqual(value.eigenvalues, [4,3])
    }

    func testExceptionalOrBelowTwoCountsDoNotInventConversion() throws {
        for count in [0.0, 1, 1.75, -.infinity, .infinity, .nan] {
            XCTAssertThrowsError(try ReferencePCALowEpoch.apply(counts: [count,2,3,4],
                descendingEigenvalues: roots, basis: basis)) {
                XCTAssertEqual($0 as? ReferencePCALowEpoch.InputError, .unsupportedCount)
            }
        }
        XCTAssertThrowsError(try ReferencePCALowEpoch.apply(counts: [2,2,2,2],
            descendingEigenvalues: [1,4,3,2], basis: basis)) {
            XCTAssertEqual($0 as? ReferencePCALowEpoch.InputError, .invalidSpectrum)
        }
    }
}
