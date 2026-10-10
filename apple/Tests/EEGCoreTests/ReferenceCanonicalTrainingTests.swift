import XCTest
@testable import EEGCore

final class ReferenceCanonicalTrainingTests: XCTestCase {
    func testPCARankPolicyIncludes99BoundaryAndPreservesEmptyBranch() throws {
        XCTAssertEqual(try ReferenceCanonicalTraining.pcaSelectedIndices(
            descendingEigenvalues: [99, 1], classCount: 2), [0])
        XCTAssertEqual(try ReferenceCanonicalTraining.pcaSelectedIndices(
            descendingEigenvalues: [99.1, 0.9], classCount: 2), [])
        XCTAssertEqual(try ReferenceCanonicalTraining.pcaSelectedIndices(
            descendingEigenvalues: [50, 30, 15, 5], classCount: 2), [0, 1, 2])
        XCTAssertEqual(try ReferenceCanonicalTraining.pcaSelectedIndices(
            descendingEigenvalues: [98, 1, 0.5, 0.5], classCount: 4), [0, 1, 2])
        XCTAssertThrowsError(try ReferenceCanonicalTraining.pcaSelectedIndices(
            descendingEigenvalues: [1, 2], classCount: 2))
    }
    func testDiagonalRootsOrderingAndResidualVarianceNormalization() throws {
        let fitted = try ReferenceCanonicalTraining.fit(within: [[4, 0], [0, 9]],
            between: [[12, 0], [0, 9]], residualDegreesOfFreedom: 20, directions: 2)
        XCTAssertEqual(fitted.eigenvalues[0], 3, accuracy: 1e-14)
        XCTAssertEqual(fitted.eigenvalues[1], 1, accuracy: 1e-14)
        XCTAssertEqual(fitted.basis[0][0], sqrt(5), accuracy: 1e-14)
        XCTAssertEqual(fitted.basis[1][1], sqrt(20.0 / 9), accuracy: 1e-14)
        XCTAssertEqual(fitted.basis[0][1], 0, accuracy: 1e-14)
    }

    func testCorrelatedScatterSatisfiesGeneralizedEigenEquation() throws {
        // E and H do not commute: catches whitening transpose mistakes.
        let e = [[4.0, 1], [1, 2]], h = [[5.0, -1], [-1, 3]]
        let fitted = try ReferenceCanonicalTraining.fit(within: e, between: h,
            residualDegreesOfFreedom: 18, directions: 2)
        // det(H-lambda E) = 7 lambda^2 - 24 lambda + 14.
        XCTAssertEqual(fitted.eigenvalues[0], (24 + sqrt(184)) / 14, accuracy: 1e-13)
        XCTAssertEqual(fitted.eigenvalues[1], (24 - sqrt(184)) / 14, accuracy: 1e-13)
        for direction in 0..<2 {
            for row in 0..<2 {
                let hb = (0..<2).reduce(0.0) { $0 + h[row][$1] * fitted.basis[$1][direction] }
                let eb = (0..<2).reduce(0.0) { $0 + e[row][$1] * fitted.basis[$1][direction] }
                XCTAssertEqual(hb, fitted.eigenvalues[direction] * eb, accuracy: 1e-12)
            }
            for other in 0..<2 {
                var projected = 0.0
                for row in 0..<2 { for column in 0..<2 {
                    projected += fitted.basis[row][direction] * e[row][column] * fitted.basis[column][other]
                } }
                XCTAssertEqual(projected / 18, direction == other ? 1 : 0, accuracy: 1e-13)
            }
        }
    }

    func testZeroAndNegativeRootsArePreservedInsteadOfInventedSignificance() throws {
        let fitted = try ReferenceCanonicalTraining.fit(within: [[1, 0], [0, 1]],
            between: [[0, 0], [0, -2]], residualDegreesOfFreedom: 10, directions: 2)
        XCTAssertEqual(fitted.eigenvalues, [0, -2])
        XCTAssertEqual(fitted.basis[0][0], sqrt(10), accuracy: 1e-13)
    }

    func testRejectsUnsupportedSingularAsymmetricAndNonFiniteInputs() {
        XCTAssertThrowsError(try ReferenceCanonicalTraining.fit(within: [[1, 1], [1, 1]],
            between: [[1, 0], [0, 1]], residualDegreesOfFreedom: 10, directions: 1))
        XCTAssertThrowsError(try ReferenceCanonicalTraining.fit(within: [[1, 0], [1, 1]],
            between: [[1, 0], [0, 1]], residualDegreesOfFreedom: 10, directions: 1))
        XCTAssertThrowsError(try ReferenceCanonicalTraining.fit(within: [[1]],
            between: [[.nan]], residualDegreesOfFreedom: 10, directions: 1))
        XCTAssertThrowsError(try ReferenceCanonicalTraining.fit(within: [[1]],
            between: [[1]], residualDegreesOfFreedom: 0, directions: 1))
        XCTAssertThrowsError(try ReferenceCanonicalTraining.fit(within: [[1]],
            between: [[1]], residualDegreesOfFreedom: 10, directions: 2))
    }
}
