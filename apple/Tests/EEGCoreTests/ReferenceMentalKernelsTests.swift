import XCTest
@testable import EEGCore

final class ReferenceMentalKernelsTests: XCTestCase {
    func testSymmetricHammingLandmarksAndOrientation() throws {
        let expected = [0.08, 0.54, 1.0, 0.54, 0.08]
        let actual = try ReferenceMentalKernels.hamming(count: 5)
        for (a, b) in zip(actual, expected) { XCTAssertEqual(a, b, accuracy: 1e-14) }
        let windowed = try ReferenceMentalKernels.window([1, 2, 3, 4, 5])
        for (a, b) in zip(windowed, [0.08, 1.08, 3, 2.16, 0.4]) {
            XCTAssertEqual(a, b, accuracy: 1e-14)
        }
        let even = try ReferenceMentalKernels.hamming(count: 256)
        for (a, b) in zip(even, even.reversed()) { XCTAssertEqual(a, b, accuracy: 1e-14) }
        XCTAssertLessThan(even[127], 1) // Symmetric, not periodic.
        XCTAssertEqual(even.first!, 0.08, accuracy: 1e-14)
        XCTAssertEqual(even.last!, 0.08, accuracy: 1e-14)
    }

    func testUnsupportedWindowInputsAreExplicit() {
        for count in [-1, 0, 1] {
            XCTAssertThrowsError(try ReferenceMentalKernels.hamming(count: count))
        }
        XCTAssertThrowsError(try ReferenceMentalKernels.window([1, .nan]))
    }

    func testFilterUsesFirstInputHistoryNotZero() throws {
        var filter = ReferenceScoringLowpass()
        let output = try filter.process([1, 0, 0, 0])
        for (a, b) in zip(output, [1, 0.8, 0.64, 0.512]) {
            XCTAssertEqual(a, b, accuracy: 1e-14)
        }
        filter.reset()
        let step = try filter.process([0, 1, 1, 1])
        for (a, b) in zip(step, [0, 0.2, 0.36, 0.488]) {
            XCTAssertEqual(a, b, accuracy: 1e-14)
        }
    }

    func testChunkBoundariesDoNotChangeArithmetic() throws {
        let samples = (0..<1024).map { sin(Double($0) * 0.13) }
        var whole = ReferenceScoringLowpass()
        let expected = try whole.process(samples)
        for size in [1, 3, 16, 255, 1024] {
            var chunked = ReferenceScoringLowpass()
            var actual: [Double] = []
            for start in stride(from: 0, to: samples.count, by: size) {
                actual += try chunked.process(Array(samples[start..<min(start + size, samples.count)]))
            }
            XCTAssertEqual(actual, expected)
        }
    }

    func testRejectedBlockAndEmptyBlockPreserveState() throws {
        var filter = ReferenceScoringLowpass()
        _ = try filter.process([1])
        XCTAssertEqual(try filter.process([]), [])
        XCTAssertThrowsError(try filter.process([0, .infinity]))
        XCTAssertEqual(try filter.process([0])[0], 0.8, accuracy: 1e-14)
        filter.reset()
        XCTAssertEqual(try filter.process([0])[0], 0)
    }
}
