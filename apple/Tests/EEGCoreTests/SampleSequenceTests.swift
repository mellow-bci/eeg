import XCTest
@testable import EEGCore

final class SampleSequenceTests: XCTestCase {
    private func sample(_ index: Int, counter: Int, time: Double = 0) -> EEGSample {
        EEGSample(index: index, counter: counter, receivedAt: time, continuous: true,
            adcWords: Array(repeating: 31200, count: 15),
            electrodesADC: Dictionary(uniqueKeysWithValues: EEGRecordingStore.channels.map { ($0, 31200) }),
            electrodesMicrovolts: Dictionary(uniqueKeysWithValues: EEGRecordingStore.channels.map { ($0, 4000) }),
            notificationSlot: 0, recordFlag: 0)
    }
    func testIntegerBoundaryAndCounterWrapAreDistinct() {
        XCTAssertTrue(sample(Int.max, counter: 0).followsIndexAndCounter(sample(Int.max - 1, counter: 127)))
        XCTAssertFalse(sample(0, counter: 0).followsIndexAndCounter(sample(Int.max, counter: 127)))
        XCTAssertFalse(sample(Int.max, counter: 0).followsIndexAndCounter(sample(Int.max, counter: 127)))
        XCTAssertFalse(sample(0, counter: 0).followsIndexAndCounter(sample(-1, counter: 127)))
        XCTAssertFalse(sample(1, counter: 0).followsIndexAndCounter(sample(0, counter: Int.max)))
        XCTAssertFalse(sample(1, counter: Int.min).followsIndexAndCounter(sample(0, counter: 0)))
        XCTAssertTrue(sample(128, counter: 0).followsIndexAndCounter(sample(127, counter: 127)))
    }
    func testSpectrumRejectsExtremeIndexRatherThanTrapping() {
        var samples = (0..<256).map { sample($0, counter: $0 % 128, time: Double($0) / 128) }
        samples[0] = sample(Int.max, counter: 0)
        XCTAssertThrowsError(try EEGSpectrum.analyze(samples: samples, channel: "AF3")) {
            XCTAssertEqual($0 as? EEGSpectrumError, .discontinuity)
        }
    }
    func testFinalizedRecordingPreservesBoundaryButRejectsAnalysisAndSplitsExport() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try EEGRecordingStore(directory: root), file = try store.start()
        let anchor = try EEGRecordingClockAnchor(receiptBefore: 0, receiptAfter: 0,
            wallUnixSeconds: 1_800_000_000, localUTCOffsetSeconds: 0)
        try store.appendEvent(kind: "recording_clock_anchor", fields: ["json": String(decoding: JSONEncoder().encode(anchor), as: UTF8.self)])
        try store.appendEvent(kind: "device_metadata", fields: ["81072f44-9f3d-11e3-a9dc-0002a5d5c51b": "018000102010"])
        try store.appendEvent(kind: "transport_status", fields: ["status": "stable"])
        try store.append(sample: sample(Int.max, counter: 127))
        try store.append(sample: sample(0, counter: 0, time: 1.0 / 128))
        try store.finish()
        let original = try Data(contentsOf: file)
        var windows = [EEGAnalysisWindow]()
        try store.analysisWindows(recording: file) { windows.append($0) }
        XCTAssertEqual(windows.count, 1)
        XCTAssertFalse(windows[0].valid)
        XCTAssertTrue(windows[0].reasons.contains("index_or_counter_gap"))
        XCTAssertEqual(windows[0].samples.map(\.index), [Int.max, 0])
        let plan = try EEGEDFNominalPlan.inspect(recording: file, store: store)
        XCTAssertEqual(plan.segments.map(\.sampleCount), [1, 1])
        XCTAssertEqual(plan.segments[1].boundaryReasons, ["index_or_counter_gap"])
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
}
