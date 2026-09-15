import XCTest
@testable import EEGCore

final class RecordingOverlapTests: XCTestCase {
    private func sample(_ index: Int, shiftedClock: Bool = false, delta: Int = 0) -> EEGSample {
        let channels = EEGMentalFeatures.channelOrder
        let words = channels.indices.map { UInt16((index * 137 + $0 * 19 + delta) % 60000) }
        return EEGSample(index: index, counter: index % 128,
            receivedAt: Double(index) / 128 + (shiftedClock ? 900 : 0), continuous: true,
            adcWords: words + [0],
            electrodesADC: Dictionary(uniqueKeysWithValues: zip(channels, words.map(Double.init))),
            electrodesMicrovolts: [:], notificationSlot: 0, recordFlag: 0)
    }
    func testShiftedExcerptAcrossDifferentLengthsAndClocksIsDetected() throws {
        var index = EEGRecordingOverlapIndex(), first = EEGRecordingOverlapIndex.Scanner()
        for i in 0..<1024 { try index.append(sample(i), to: &first) }
        XCTAssertFalse(first.reusedBlock)
        index.commit(first)
        var second = EEGRecordingOverlapIndex.Scanner()
        // Offset is deliberately not aligned to a 256-sample analysis window.
        for i in 37..<800 { try index.append(sample(i, shiftedClock: true), to: &second) }
        XCTAssertTrue(second.reusedBlock)
    }
    func testExactBlockAndUnrelatedData() throws {
        var index = EEGRecordingOverlapIndex(), first = EEGRecordingOverlapIndex.Scanner()
        for i in 0..<768 { try index.append(sample(i), to: &first) }
        index.commit(first)
        var exact = EEGRecordingOverlapIndex.Scanner(), changed = EEGRecordingOverlapIndex.Scanner()
        for i in 256..<512 {
            try index.append(sample(i), to: &exact)
            try index.append(sample(i, delta: 1), to: &changed)
        }
        XCTAssertTrue(exact.reusedBlock)
        XCTAssertFalse(changed.reusedBlock)
    }
    func testMinimumGuaranteedExcerptAtEveryBlockAlignment() throws {
        var index = EEGRecordingOverlapIndex(), first = EEGRecordingOverlapIndex.Scanner()
        for i in 0..<1024 { try index.append(sample(i), to: &first) }
        index.commit(first)
        for offset in 0..<256 {
            var excerpt = EEGRecordingOverlapIndex.Scanner()
            for i in offset..<(offset + 511) { try index.append(sample(i), to: &excerpt) }
            XCTAssertTrue(excerpt.reusedBlock, "Undetected offset \(offset)")
        }
    }
    func testShortExcerptIsNotClaimedAsDetected() throws {
        var index = EEGRecordingOverlapIndex(), first = EEGRecordingOverlapIndex.Scanner()
        for i in 0..<512 { try index.append(sample(i), to: &first) }
        index.commit(first)
        var short = EEGRecordingOverlapIndex.Scanner()
        for i in 0..<255 { try index.append(sample(i), to: &short) }
        XCTAssertFalse(short.reusedBlock)
    }
}
