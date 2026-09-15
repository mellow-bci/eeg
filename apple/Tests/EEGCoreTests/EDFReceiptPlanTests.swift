import XCTest
@testable import EEGCore

final class EDFReceiptPlanTests: XCTestCase {
    private func fixture(anchor: Bool = true, configuration: String = "018000102010", complete: Bool = true, times: [Double] = [0.02, 0.02, 2.0]) throws -> (EEGRecordingStore, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try EEGRecordingStore(directory: root), file = try store.start()
        if anchor {
            let observation = try EEGRecordingClockAnchor(receiptBefore: 0, receiptAfter: 0.01, wallUnixSeconds: 1_800_000_000, localUTCOffsetSeconds: 0)
            try store.appendEvent(kind: "recording_clock_anchor", fields: ["json": String(decoding: JSONEncoder().encode(observation), as: UTF8.self)])
        }
        try store.appendEvent(kind: "device_metadata", fields: ["81072f44-9f3d-11e3-a9dc-0002a5d5c51b": configuration])
        try store.appendEvent(kind: "transport_status", fields: ["status": "stable"])
        for (i, time) in times.enumerated() {
            let value = UInt16(i == 0 ? 0 : i == 1 ? 32768 : 65535)
            try store.append(sample: EEGSample(index: i, counter: i, receivedAt: time, continuous: i != 2,
                adcWords: Array(repeating: value, count: 15),
                electrodesADC: Dictionary(uniqueKeysWithValues: EEGRecordingStore.channels.map { ($0, Double(value)) }),
                electrodesMicrovolts: nil, notificationSlot: 0, recordFlag: 0))
        }
        if complete { try store.finish() } else { store.abort() }
        return (store, file, root)
    }
    func testPreservesTailsRepeatedTimesGapsAndUnsignedRange() throws {
        let (store, file, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try Data(contentsOf: file)
        let plan = try EEGEDFReceiptPlan.inspect(recording: file, store: store)
        XCTAssertEqual(plan.sampleCount, 3)
        XCTAssertEqual(plan.repeatedReceiptTimes, 1)
        XCTAssertEqual(plan.firstReceiptSeconds, 0.02)
        XCTAssertEqual(plan.lastReceiptSeconds, 2)
        XCTAssertEqual(plan.channelADCRanges.count, 14)
        XCTAssertTrue(plan.channelADCRanges.values.allSatisfy { $0 == 0...65535 })
        XCTAssertTrue(plan.analysisWarnings.contains("partial_window"))
        XCTAssertTrue(plan.analysisWarnings.contains("arrival_gap"))
        XCTAssertTrue(plan.analysisWarnings.contains("sample_discontinuity"))
        XCTAssertFalse(plan.exportEnabled)
        XCTAssertEqual(plan.sourceSHA256, try store.clockEvidence(recording: file).fileSHA256)
        XCTAssertGreaterThan(plan.firstWallTimeBounds.upperBound, plan.firstWallTimeBounds.lowerBound)
        XCTAssertEqual(try Data(contentsOf: file), original)
        for value in UInt32(0)...UInt32(65535) {
            XCTAssertEqual(Int(EEGEDFReceiptPlan.signedADC(UInt16(value))) + 32768, Int(value))
        }
    }
    func testEmptyAndBackwardsReceiptSourcesRejected() throws {
        for times: [Double] in [[], [2.0, 1.0]] {
            let (store, file, root) = try fixture(times: times)
            defer { try? FileManager.default.removeItem(at: root) }
            XCTAssertThrowsError(try EEGEDFReceiptPlan.inspect(recording: file, store: store))
        }
    }
    func testMissingAnchorUnsupportedConfigurationAndIncompleteSourceRejected() throws {
        for option in 0..<3 {
            let (store, file, root) = try fixture(anchor: option != 0, configuration: option == 1 ? "unknown" : "018000102010", complete: option != 2)
            defer { try? FileManager.default.removeItem(at: root) }
            XCTAssertThrowsError(try EEGEDFReceiptPlan.inspect(recording: file, store: store))
        }
    }
}
