import XCTest
@testable import EEGCore

final class ReferenceSpectralPipelineTests: XCTestCase {
    func testMedianReductionUsesRowsAtEachColumn() throws {
        XCTAssertEqual(try ReferenceSpectralPipeline.preprocess([[1, 100], [3, 0], [99, 10]]),
                       [[-2, 90], [0, -10], [96, 0]])
        XCTAssertEqual(try ReferenceSpectralPipeline.preprocess([[1, 10], [5, 20]]),
                       [[-2, -5], [2, 5]])
        XCTAssertThrowsError(try ReferenceSpectralPipeline.preprocess([[1], [2, 3]]))
        XCTAssertThrowsError(try ReferenceSpectralPipeline.preprocess([[.nan]]))
    }
    func testDCImpulseToneAndNyquist() throws {
        let n = 32
        XCTAssertEqual(try ReferenceSpectralPipeline.spectrum(Array(repeating: 1, count: n))[0], 4)
        let impulse = try ReferenceSpectralPipeline.spectrum([1] + Array(repeating: 0, count: n-1))
        for value in impulse { XCTAssertEqual(value, 4 / Double(n*n), accuracy: 1e-14) }
        let tone = (0..<n).map { cos(2 * Double.pi * 3 * Double($0) / Double(n)) }
        let bins = try ReferenceSpectralPipeline.spectrum(tone)
        XCTAssertEqual(bins.count, n/2)
        for i in bins.indices { XCTAssertEqual(bins[i], i == 3 ? 1 : 0, accuracy: 1e-13) }
        let nyquist = try ReferenceSpectralPipeline.spectrum((0..<n).map { $0 % 2 == 0 ? 1 : -1 })
        XCTAssertTrue(nyquist.allSatisfy { abs($0) < 1e-13 })
    }
    func testInclusiveCeilBandMeanAndClamp() throws {
        let output = try ReferenceSpectralPipeline.bands([1, 2, 3, 4], sampleRate: 8,
            bands: [.init(lowerHz: 0.1, upperHz: 2.1), .init(lowerHz: 2, upperHz: 4)])
        XCTAssertEqual(output, [6, 7])
        XCTAssertThrowsError(try ReferenceSpectralPipeline.spectrum([1, 2, 3]))
        XCTAssertThrowsError(try ReferenceSpectralPipeline.spectrum([1, .nan]))
    }
}
