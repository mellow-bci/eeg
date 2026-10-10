import XCTest
@testable import EEGCore

final class ReferenceTrainingStatisticsTests: XCTestCase {
    func testUnbiasedFeatureCovariance() throws {
        let result = try ReferenceTrainingStatistics.fit(featureRows: [[1, 2, 3], [2, 4, 8]], coordinates: [0, 1], maximumEpochs: 100)
        XCTAssertEqual(result.average[0], 2)
        XCTAssertEqual(result.average[1], 14.0 / 3, accuracy: 1e-12)
        XCTAssertEqual(result.covariance[0][0], 1, accuracy: 1e-12)
        XCTAssertEqual(result.covariance[0][1], 3, accuracy: 1e-12)
        XCTAssertEqual(result.covariance[1][0], 3, accuracy: 1e-12)
        XCTAssertEqual(result.covariance[1][1], 28.0 / 3, accuracy: 1e-12)
        XCTAssertEqual(result.epochCounts, [3, 3])
    }
    func testCoordinatePermutation() throws {
        let result = try ReferenceTrainingStatistics.fit(featureRows: [[1, 3], [10, 14]], coordinates: [1, 0], maximumEpochs: 100)
        XCTAssertEqual(result.average, [12, 2])
        XCTAssertEqual(result.covariance, [[8, 4], [4, 2]])
    }
    func testDuplicateCoordinateOverwritesAndUnassignedIsZero() throws {
        let result = try ReferenceTrainingStatistics.fit(featureRows: [[1, 3], [10, 14]], coordinates: [0, 0], maximumEpochs: 100)
        XCTAssertEqual(result.average, [12, 0])
        XCTAssertEqual(result.epochCounts, [2, 0])
        XCTAssertEqual(result.covariance, [[8, 0], [0, 0]])
    }
    func testConstantFeaturesHaveZeroCovariance() throws {
        let result = try ReferenceTrainingStatistics.fit(featureRows: [[4, 4, 4]], coordinates: [0], maximumEpochs: 100)
        XCTAssertEqual(result.average, [4])
        XCTAssertEqual(result.covariance, [[0]])
    }
    func testRejectsInvalidAndUnsupportedInputs() {
        let inputs: [[[Double]]] = [[], [[1]], [[1, 2], [3]], [[Double.nan, 2]]]
        for rows in inputs {
            XCTAssertThrowsError(try ReferenceTrainingStatistics.fit(featureRows: rows, coordinates: [0], maximumEpochs: 100))
        }
        XCTAssertThrowsError(try ReferenceTrainingStatistics.fit(featureRows: [[1, 2, 3]], coordinates: [0], maximumEpochs: 2))
        XCTAssertThrowsError(try ReferenceTrainingStatistics.fit(featureRows: [[1, 2]], coordinates: [0], maximumEpochs: 1))
        XCTAssertThrowsError(try ReferenceTrainingStatistics.fit(featureRows: [[1, 2]], coordinates: [1], maximumEpochs: 100))
        XCTAssertThrowsError(try ReferenceTrainingStatistics.fit(featureRows: [[1, 2]], coordinates: [], maximumEpochs: 100))
        XCTAssertThrowsError(try ReferenceTrainingStatistics.fit(featureRows: [[Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude]], coordinates: [0], maximumEpochs: 100))
    }
}
