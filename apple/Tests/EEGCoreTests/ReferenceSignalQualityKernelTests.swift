import XCTest
@testable import EEGCore

final class ReferenceSignalQualityKernelTests: XCTestCase {
    private func score(_ density: Double, rms: Double = 2, contact: [Int] = [4], combine: Bool = true) throws -> ReferenceSignalQualityKernel.Scores {
        try ReferenceSignalQualityKernel.scores(logDensity: density, rms: rms,
            scoreThresholds: [0,1,2], rmsThresholds: [1,3], internalRMSThresholds: [0.5,1.5],
            contactStates: contact, combineWithContact: combine, maximumContactStates: 8)
    }
    func testNumericalFeaturesAndUncenteredRMS() throws {
        let f = try ReferenceSignalQualityKernel.features([1,3,-1], maximumSamples: 3)
        XCTAssertEqual(f.rms, sqrt(11.0/3), accuracy: 1e-12)
        XCTAssertEqual(f.rmsDifference, sqrt(10), accuracy: 1e-12)
        XCTAssertEqual(f.range, 4)
        let constant = try ReferenceSignalQualityKernel.features([5,5,5], maximumSamples: 3)
        XCTAssertEqual(constant.rms, 5); XCTAssertEqual(constant.rmsDifference, 0)
        XCTAssertEqual(constant.range, 0)
    }
    func testGaussianThresholdsAreInclusiveAndSkipStateTwo() throws {
        for (density, expected) in [(-1.0,4),(-10,3),(-100,1),(-1000,0),(0,0)] {
            XCTAssertEqual(try score(density).gaussianState, expected)
        }
        XCTAssertEqual(try score(-10).transformedLogDensity, 1)
    }
    func testAmplitudeBoundariesAndIndependentInternalThresholds() throws {
        XCTAssertEqual(try score(-1, rms: 0.99).rmsState, 0)
        XCTAssertEqual(try score(-1, rms: 1).rmsState, 4)
        XCTAssertEqual(try score(-1, rms: 3).rmsState, 4)
        XCTAssertEqual(try score(-1, rms: 3.01).rmsState, 1)
        XCTAssertEqual(try score(-1).combinedState, 4)
        XCTAssertEqual(try score(-1).internalCombinedState, 1)
    }
    func testContactFusionSpecialBranchesAndEmptyMinimum() throws {
        XCTAssertEqual(try score(-1, contact: [4,1]).combinedState, 0)
        XCTAssertEqual(try score(-1, contact: [2]).combinedState, 1)
        XCTAssertEqual(try score(-1000, contact: [4]).combinedState, 1)
        XCTAssertEqual(try score(-100, contact: [3]).combinedState, 3)
        XCTAssertEqual(try score(-1, contact: [], combine: false).minimumContactState, 4)
        XCTAssertEqual(try score(-1, contact: [3], combine: false).combinedState, 3)
    }
    func testUnsupportedNumericalAndCapacityInputsAreExplicit() throws {
        XCTAssertThrowsError(try ReferenceSignalQualityKernel.features([1], maximumSamples: 2))
        XCTAssertThrowsError(try ReferenceSignalQualityKernel.features([1,2,3], maximumSamples: 2))
        XCTAssertThrowsError(try ReferenceSignalQualityKernel.features([1,.nan], maximumSamples: 2))
        XCTAssertThrowsError(try score(1)); XCTAssertThrowsError(try score(-.infinity))
        XCTAssertThrowsError(try score(-1, contact: [5]))
    }
}
