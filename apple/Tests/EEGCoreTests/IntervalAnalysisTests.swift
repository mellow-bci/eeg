import Foundation
import XCTest
@testable import EEGCore

final class IntervalAnalysisTests: XCTestCase {
    private func samples(_ count: Int, shiftedAt: Int? = nil, flat: Bool = false) -> [EEGSample] {
        (0..<count).map { index in
            let adc = flat ? 31200.0 : (31200 + 156 * sin(2 * .pi * 10 * Double(index) / 128)).rounded()
            let shift = shiftedAt.map { index >= $0 ? 1 : 0 } ?? 0
            let actualIndex = index + shift
            let channels = Dictionary(uniqueKeysWithValues: EPOCProtocol.electrodeWords.map { ($0.name, adc) })
            return EEGSample(index: actualIndex, counter: actualIndex % 128, receivedAt: Double(actualIndex) / 128,
                             continuous: true, adcWords: [UInt16](repeating: UInt16(adc), count: 15),
                             electrodesADC: channels, electrodesMicrovolts: channels.mapValues { $0 / 7.8 },
                             notificationSlot: index % 2, recordFlag: 0)
        }
    }
    func testOneWindowEqualsVerifiedSpectrum() throws {
        let input = samples(256)
        let result = try EEGIntervalAnalysis.analyze(samples: input, channel: "AF3")
        let direct = try EEGSpectrum.analyze(samples: input, channel: "AF3")
        XCTAssertEqual(result.windows.count, 1)
        XCTAssertEqual(result.acceptedWindowCount, 1)
        XCTAssertEqual(result.frequenciesHz, direct.frequenciesHz)
        XCTAssertEqual(result.meanDensityMicrovoltsSquaredPerHz, direct.densityMicrovoltsSquaredPerHz)
        XCTAssertEqual(result.windows[0].startIndex, 0)
        XCTAssertEqual(result.windows[0].endIndex, 255)
        XCTAssertEqual(result.windows[0].centerIndex, 127.5)
        XCTAssertEqual(result.windows[0].centerTime, 127.5 / 128)
    }
    func testOverlappingWindowsAndTrailingUncoveredCount() throws {
        let result = try EEGIntervalAnalysis.analyze(samples: samples(600), channel: "O1")
        XCTAssertEqual(result.windows.map(\.startIndex), [0, 128, 256])
        XCTAssertEqual(result.windows.map(\.endIndex), [255, 383, 511])
        XCTAssertEqual(result.acceptedWindowCount, 3)
        XCTAssertEqual(result.trailingUncoveredSampleCount, 88)
        XCTAssertEqual(result.hopSize, 128)
        XCTAssertEqual(result.windowSize, 256)
    }
    func testGapCrossingWindowsRejectedAndMeanExcludesThem() throws {
        // The real index/counter gap is at array offset 256. Only the middle
        // sliding window crosses it; neither neighboring window bridges it.
        let input = samples(512, shiftedAt: 256)
        let result = try EEGIntervalAnalysis.analyze(samples: input, channel: "AF3")
        XCTAssertEqual(result.windows.map(\.accepted), [true, false, true])
        XCTAssertNotNil(result.windows[1].rejectionReason)
        XCTAssertNil(result.windows[1].densityMicrovoltsSquaredPerHz)
        let a = try EEGSpectrum.analyze(samples: Array(input[0..<256]), channel: "AF3")
        let b = try EEGSpectrum.analyze(samples: Array(input[256..<512]), channel: "AF3")
        let expected = zip(a.densityMicrovoltsSquaredPerHz, b.densityMicrovoltsSquaredPerHz).map { ($0 + $1) / 2 }
        XCTAssertEqual(result.meanDensityMicrovoltsSquaredPerHz, expected)
        XCTAssertEqual(result.rejectedWindowCount, 1)
        XCTAssertEqual(result.windows[2].startIndex, 257)
    }
    func testArtifactFlagsRetainedButNotConfusedWithStructuralRejection() throws {
        let result = try EEGIntervalAnalysis.analyze(samples: samples(384, flat: true), channel: "AF3")
        XCTAssertEqual(result.acceptedWindowCount, 2)
        XCTAssertEqual(result.rejectedWindowCount, 0)
        XCTAssertEqual(result.flaggedWindowCount, 2)
        XCTAssertTrue(result.windows.allSatisfy { $0.artifactFlags == ["flat_channel"] })
        XCTAssertTrue(result.averagingMethod.contains("structurally valid"))
    }
    func testAllRejectedHasNoFabricatedMeanAndShortInputFails() throws {
        XCTAssertThrowsError(try EEGIntervalAnalysis.analyze(samples: samples(255), channel: "AF3"))
        XCTAssertThrowsError(try EEGIntervalAnalysis.analyze(samples: samples(256), channel: "unknown"))
        let result = try EEGIntervalAnalysis.analyze(samples: samples(256, shiftedAt: 128), channel: "AF3")
        XCTAssertEqual(result.rejectedWindowCount, 1)
        XCTAssertNil(result.meanDensityMicrovoltsSquaredPerHz)
    }
}
