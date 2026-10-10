import XCTest
@testable import EEGCore

final class ReferencePCAFittingTests: XCTestCase {
    func testWeightedCenterAndPooledCovarianceDeterminePCA() throws {
        let first = ReferenceGaussianPooling.Distribution(counts: [10, 10], mean: [0, 0],
            covariance: [[4, 0], [0, 1]], updateTime: 10)
        let second = ReferenceGaussianPooling.Distribution(counts: [30, 30], mean: [2, 0],
            covariance: [[4, 0], [0, 1]], updateTime: 30)
        let fit = try ReferencePCAFitting.fit(classes: [first, second])
        XCTAssertEqual(fit.pooled.mean, [1.5, 0])
        XCTAssertEqual(fit.pooled.counts, [40, 40])
        XCTAssertEqual(fit.pooled.updateTime, 20)
        XCTAssertEqual(fit.eigenvalues[0], 182.0 / 39, accuracy: 1e-12)
        XCTAssertEqual(fit.eigenvalues[1], 38.0 / 39, accuracy: 1e-12)
        XCTAssertEqual(fit.selectedIndices, [0])
        let transform = try XCTUnwrap(fit.transform)
        XCTAssertEqual(transform.mean, [1.5, 0])
        XCTAssertEqual(transform.basis[0][0], 1, accuracy: 1e-12)
        XCTAssertEqual(transform.basis[1][0], 0, accuracy: 1e-12)
    }

    func testDominantFirstComponentDoesNotInventMinimumRank() throws {
        let value = ReferenceGaussianPooling.Distribution(counts: [10, 10], mean: [0, 0],
            covariance: [[1000, 0], [0, 1]], updateTime: 0)
        let fit = try ReferencePCAFitting.fit(classes: [value, value])
        XCTAssertEqual(fit.selectedIndices, [])
        XCTAssertNil(fit.transform)
    }

    func testLowEpochAndInsufficientClassesAreExplicitFailures() throws {
        let value = ReferenceGaussianPooling.Distribution(counts: [1, 1], mean: [0, 0],
            covariance: [[1, 0], [0, 1]], updateTime: 0)
        XCTAssertThrowsError(try ReferencePCAFitting.fit(classes: [value])) {
            XCTAssertEqual($0 as? ReferencePCAFitting.InputError, .invalidClasses)
        }
        // One empty accumulator copies this class. A second Gaussian with zero
        // supported counts cannot be silently turned into a covariance fit.
        XCTAssertThrowsError(try ReferencePCAFitting.fit(classes: [value, value]))
        let low = ReferenceGaussianPooling.Distribution(counts: [2, 2, 2, 2], mean: [0, 0, 0, 0],
            covariance: [[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]], updateTime: 0)
        XCTAssertThrowsError(try ReferencePCAFitting.fit(classes: [low, low])) {
            XCTAssertEqual($0 as? ReferencePCAFitting.InputError, .lowEpochClippingUnsupported)
        }
    }
}
