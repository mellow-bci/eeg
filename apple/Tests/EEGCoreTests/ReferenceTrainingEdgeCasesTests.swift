import XCTest
@testable import EEGCore

final class ReferenceTrainingEdgeCasesTests: XCTestCase {
    func testSingletonOneFeatureZeroVarianceAndCounts() throws {
        let result = try ReferenceTrainingEdgeCases.singletonStatistics(featureRows: [[17]], coordinates: [0])
        XCTAssertEqual(result.average, [17]); XCTAssertEqual(result.covariance, [[0]])
        XCTAssertEqual(result.epochCounts, [1])
        XCTAssertThrowsError(try ReferenceTrainingEdgeCases.singletonStatistics(featureRows: [[1], [2]], coordinates: [0, 1]))
        XCTAssertThrowsError(try ReferenceTrainingEdgeCases.singletonStatistics(featureRows: [[.nan]], coordinates: [0]))
    }
    func testSingularPCARetainsZeroRoots() throws {
        let result = try ReferenceTrainingEdgeCases.singularPCA(covariance: [[50, 0, 0, 0], [0, 30, 0, 0], [0, 0, 20, 0], [0, 0, 0, 0]], classCount: 2)
        XCTAssertEqual(result.eigenvalues, [50, 30, 20, 0])
        XCTAssertEqual(result.selectedIndices, [0, 1])
        for column in 0..<4 {
            for row in 0..<4 {
                let diagonal = [50.0, 30, 20, 0][row]
                XCTAssertEqual(diagonal * result.basis[row][column], result.eigenvalues[column] * result.basis[row][column], accuracy: 1e-12)
            }
        }
    }
    func testZeroCovarianceAndDominantRootClearPCABasisSelection() throws {
        XCTAssertEqual(try ReferenceTrainingEdgeCases.singularPCA(covariance: [[0, 0], [0, 0]], classCount: 2).selectedIndices, [])
        XCTAssertEqual(try ReferenceTrainingEdgeCases.singularPCA(covariance: [[1, 0], [0, 0]], classCount: 2).selectedIndices, [])
        XCTAssertThrowsError(try ReferenceTrainingEdgeCases.singularPCA(covariance: [[1, 0], [0, -1]], classCount: 2))
    }
    func testBoundedCanonicalRepairReportsChangedMeasurements() throws {
        let result = try ReferenceTrainingEdgeCases.boundedCanonical(within: [[0, 0], [0, 0]], between: [[2, 0], [0, 1]], residualDegreesOfFreedom: 10, directions: 2, maximumDiagonalAdditions: 1)
        XCTAssertEqual(result.diagonalAdditions, 1)
        XCTAssertEqual(result.repairedWithin, [[1e-10, 0], [0, 1e-10]])
        XCTAssertEqual(result.fit.eigenvalues[0], 2e10, accuracy: 1e-4)
        XCTAssertEqual(result.fit.eigenvalues[1], 1e10, accuracy: 1e-4)
        XCTAssertThrowsError(try ReferenceTrainingEdgeCases.boundedCanonical(within: [[0]], between: [[1]], residualDegreesOfFreedom: 10, directions: 1, maximumDiagonalAdditions: 0))
        XCTAssertThrowsError(try ReferenceTrainingEdgeCases.boundedCanonical(within: [[-1]], between: [[1]], residualDegreesOfFreedom: 10, directions: 1, maximumDiagonalAdditions: 2))
    }
    func testCanonicalStrictBranchNeedsNoRepair() throws {
        let result = try ReferenceTrainingEdgeCases.boundedCanonical(within: [[4]], between: [[12]], residualDegreesOfFreedom: 20, directions: 1, maximumDiagonalAdditions: 1)
        XCTAssertEqual(result.diagonalAdditions, 0)
        XCTAssertEqual(result.fit.eigenvalues, [3])
        XCTAssertEqual(result.repairedWithin, [[4]])
    }
    func testEmptySharedPoolingClearsVectorsRetainsCovariance() throws {
        let a = ReferenceGaussianPooling.Distribution(counts: [3, 0.5], mean: [1, 2], covariance: [[2, 0], [0, 3]], updateTime: UInt32.max)
        let b = ReferenceGaussianPooling.Distribution(counts: [1, 4], mean: [3, 4], covariance: [[8, 0], [0, 9]], updateTime: 3)
        let result = try ReferenceTrainingEdgeCases.emptySharedPooling(a, b, useFirstUpdateTime: false)
        XCTAssertEqual(result.counts, []); XCTAssertEqual(result.mean, [])
        XCTAssertEqual(result.retainedCovariance, b.covariance)
        XCTAssertEqual(result.updateTime, 1); XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(try ReferenceTrainingEdgeCases.emptySharedPooling(a, b, useFirstUpdateTime: true).updateTime, UInt32.max)
    }
    func testEmptySharedKernelRejectsOtherPaths() {
        let a = ReferenceGaussianPooling.Distribution(counts: [3], mean: [1], covariance: [[2]], updateTime: 10)
        let empty = ReferenceGaussianPooling.Distribution(counts: [1], mean: [1], covariance: [[2]], updateTime: 10)
        XCTAssertThrowsError(try ReferenceTrainingEdgeCases.emptySharedPooling(a, a, useFirstUpdateTime: false))
        XCTAssertThrowsError(try ReferenceTrainingEdgeCases.emptySharedPooling(a, empty, useFirstUpdateTime: false))
    }
}
