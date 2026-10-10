import XCTest
@testable import EEGCore

final class ReferenceGaussianPoolingTests: XCTestCase {
    private typealias Pool = ReferenceGaussianPooling

    func testUniformCountsMatchDirectSampleCovariance() throws {
        let a = [[1.0, 2], [3, 1], [2, 5]]
        let b = [[4.0, 6], [0, 3], [5, 4], [2, 0]]
        let pooled = try XCTUnwrap(Pool.combine(statistics(a, time: 9), statistics(b, time: 20),
                                                useFirstUpdateTime: false))
        let expected = statistics(a + b, time: 14)
        XCTAssertEqual(pooled.counts, expected.counts)
        XCTAssertEqual(pooled.updateTime, 14)
        for i in 0..<2 {
            XCTAssertEqual(pooled.mean[i], expected.mean[i], accuracy: 1e-14)
            for j in 0..<2 {
                XCTAssertEqual(pooled.covariance[i][j], expected.covariance[i][j], accuracy: 1e-13)
            }
        }
    }

    func testUnequalFeatureCountsUseMinimumOfSumsForDenominator() throws {
        let a = Pool.Distribution(counts: [3, 7], mean: [0, 0],
                                  covariance: [[2, 1], [1, 4]], updateTime: 10)
        let b = Pool.Distribution(counts: [8, 4], mean: [0, 0],
                                  covariance: [[3, 2], [2, 5]], updateTime: 20)
        let pooled = try XCTUnwrap(Pool.combine(a, b, useFirstUpdateTime: true))
        XCTAssertEqual(pooled.counts, [11, 11])
        XCTAssertEqual(pooled.mean, [0, 0])
        XCTAssertEqual(pooled.covariance[0][0], 2.5, accuracy: 1e-14)
        XCTAssertEqual(pooled.covariance[1][1], 3.9, accuracy: 1e-14)
        // (min(3,7)-1)*1 + (min(8,4)-1)*2 = 8; min(11,11)-1 = 10.
        XCTAssertEqual(pooled.covariance[0][1], 0.8, accuracy: 1e-14)
        XCTAssertEqual(pooled.covariance[1][0], 0.8, accuracy: 1e-14)
        XCTAssertEqual(pooled.updateTime, 10)
    }

    func testMasksKeepUnselectedCellsFromLargerMinimumCountInput() throws {
        let a = Pool.Distribution(counts: [1, 3, 4], mean: [99, 2, 4],
                                  covariance: [[8, 7, 6], [7, 2, 0], [6, 0, 3]], updateTime: 3)
        let b = Pool.Distribution(counts: [2, 5, 6], mean: [11, 6, 8],
                                  covariance: [[9, 8, 7], [8, 4, 1], [7, 1, 5]], updateTime: 6)
        let pooled = try XCTUnwrap(Pool.combine(a, b, useFirstUpdateTime: false))
        XCTAssertEqual(pooled.counts, [2, 8, 10])
        XCTAssertEqual(pooled.mean[0], 11)
        XCTAssertEqual(pooled.mean[1], 4.5)
        XCTAssertEqual(pooled.mean[2], 6.4)
        XCTAssertEqual(pooled.covariance[0], b.covariance[0])
        XCTAssertEqual(pooled.covariance[1][0], b.covariance[1][0])
        XCTAssertEqual(pooled.covariance[2][0], b.covariance[2][0])
        XCTAssertEqual(pooled.covariance[1][1], 50.0 / 7, accuracy: 1e-13)
        XCTAssertEqual(pooled.updateTime, 4)
    }

    func testEmptyInputsTiesTimestampWrapAndUnsupportedMeasurements() throws {
        let a = Pool.Distribution(counts: [2, 1], mean: [0, 9], covariance: [[2, 7], [7, 8]],
                                  updateTime: UInt32.max)
        var b = a
        b.mean[1] = 19
        b.covariance[1][1] = 18
        b.updateTime = 3
        XCTAssertNil(try Pool.combine(nil, nil, useFirstUpdateTime: true))
        XCTAssertEqual(try Pool.combine(a, nil, useFirstUpdateTime: false), a)
        XCTAssertEqual(try Pool.combine(nil, b, useFirstUpdateTime: true), b)
        let pooled = try XCTUnwrap(Pool.combine(a, b, useFirstUpdateTime: false))
        XCTAssertEqual(pooled.mean[1], 9) // minimum-count tie chooses first
        XCTAssertEqual(pooled.covariance[1][1], 8)
        XCTAssertEqual(pooled.updateTime, 1) // (UInt32.max + 3) wraps to 2
        var invalid = a
        invalid.counts = [1, 1]
        XCTAssertThrowsError(try Pool.combine(invalid, invalid, useFirstUpdateTime: true)) {
            XCTAssertEqual($0 as? Pool.PoolingError, .noSharedSupportedFeatures)
        }
        invalid = a
        invalid.mean[0] = .nan
        XCTAssertThrowsError(try Pool.combine(invalid, nil, useFirstUpdateTime: true))
        invalid = a
        invalid.covariance = [[1]]
        XCTAssertThrowsError(try Pool.combine(invalid, a, useFirstUpdateTime: true))
        invalid = a
        invalid.counts[0] = -1
        XCTAssertThrowsError(try Pool.combine(invalid, a, useFirstUpdateTime: true))
        invalid = a
        invalid.mean[0] = Double.greatestFiniteMagnitude
        XCTAssertThrowsError(try Pool.combine(invalid, invalid, useFirstUpdateTime: true))
        XCTAssertEqual(a.mean, [0, 9]) // value-type inputs preserved
    }

    private func statistics(_ rows: [[Double]], time: UInt32) -> Pool.Distribution {
        let n = Double(rows.count), dimension = rows[0].count
        let mean = (0..<dimension).map { column in rows.reduce(0.0) { $0 + $1[column] } / n }
        let covariance = (0..<dimension).map { i in
            (0..<dimension).map { j in
                rows.reduce(0.0) { $0 + ($1[i] - mean[i]) * ($1[j] - mean[j]) } / (n - 1)
            }
        }
        return .init(counts: Array(repeating: n, count: dimension), mean: mean,
                     covariance: covariance, updateTime: time)
    }
}
