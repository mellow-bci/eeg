import XCTest
@testable import EEGCore

final class EDFNominalPlanTests: XCTestCase {
    private func recording(count: Int = 259,
                           before: (Int, EEGRecordingStore) throws -> Void = { _, _ in },
                           sample: (Int) -> (Int, Int, Double, Bool) = { ($0, $0 % 128, Double($0) / 128, true) }) throws -> (EEGRecordingStore, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try EEGRecordingStore(directory: root), file = try store.start()
        let anchor = try EEGRecordingClockAnchor(receiptBefore: 0, receiptAfter: 0.01,
            wallUnixSeconds: 1_800_000_000, localUTCOffsetSeconds: 0)
        try store.appendEvent(kind: "recording_clock_anchor", fields: ["json": String(decoding: JSONEncoder().encode(anchor), as: UTF8.self)])
        try store.appendEvent(kind: "device_metadata", fields: ["81072f44-9f3d-11e3-a9dc-0002a5d5c51b": "018000102010"])
        try store.appendEvent(kind: "transport_status", fields: ["status": "stable"])
        for i in 0..<count {
            try before(i, store)
            let (index, counter, time, continuous) = sample(i)
            try store.append(sample: EEGSample(index: index, counter: counter, receivedAt: time,
                continuous: continuous, adcWords: Array(repeating: 32768, count: 15),
                electrodesADC: Dictionary(uniqueKeysWithValues: EEGRecordingStore.channels.map { ($0, 32768) }),
                electrodesMicrovolts: nil, notificationSlot: 0, recordFlag: 0))
        }
        try store.finish()
        return (store, file, root)
    }

    func testContinuousRunPreservesPartialTailAndOriginalEvidence() throws {
        let (store, file, root) = try recording()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try Data(contentsOf: file)
        let plan = try EEGEDFNominalPlan.inspect(recording: file, store: store)
        XCTAssertFalse(plan.exportEnabled)
        XCTAssertEqual(plan.segments.count, 1)
        let segment = try XCTUnwrap(plan.segments.first)
        XCTAssertEqual(segment.sampleCount, 259)
        XCTAssertEqual(segment.firstSourceSampleOrdinal, 0)
        XCTAssertEqual(segment.lastSampleIndex, 258)
        XCTAssertEqual(segment.nominalDurationSeconds, 259.0 / 128)
        XCTAssertEqual(segment.nominalLastSampleSeconds, 258.0 / 128)
        XCTAssertTrue(plan.source.analysisWarnings.contains("partial_window"))
        XCTAssertEqual(segment.firstWallTimeBounds, plan.source.firstWallTimeBounds)
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testSampleBoundariesWithinAndAcrossAnalysisWindows() throws {
        let (store, file, root) = try recording(count: 520, sample: { i in
            // A gap inside the first analysis window and a flag exactly at the
            // next window boundary must become precise export boundaries.
            (i + (i >= 129 ? 2 : 0), (i + (i >= 129 ? 2 : 0)) % 128,
             Double(i) / 128 + (i >= 129 ? 1 : 0), i != 256)
        })
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = try EEGEDFNominalPlan.inspect(recording: file, store: store)
        XCTAssertEqual(plan.segments.map(\.sampleCount), [129, 127, 264])
        XCTAssertEqual(plan.segments.map(\.firstSourceSampleOrdinal), [0, 129, 256])
        XCTAssertEqual(plan.segments[1].boundaryReasons, ["arrival_gap", "index_or_counter_gap"])
        XCTAssertEqual(plan.segments[2].boundaryReasons, ["sample_discontinuity"])
        XCTAssertEqual(plan.segments.reduce(0) { $0 + $1.sampleCount }, 520)
    }

    func testTransportAndMetadataBoundariesDoNotDiscardSamples() throws {
        let (store, file, root) = try recording(count: 5, before: { i, store in
            if i == 2 {
                try store.appendEvent(kind: "decode_error", fields: [:])
                try store.appendEvent(kind: "transport_status", fields: ["status": "stable"])
            }
            if i == 4 {
                try store.appendEvent(kind: "device_metadata", fields: ["81072f44-9f3d-11e3-a9dc-0002a5d5c51b": "018000102010"])
            }
        })
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = try EEGEDFNominalPlan.inspect(recording: file, store: store)
        XCTAssertEqual(plan.segments.map(\.sampleCount), [2, 2, 1])
        XCTAssertEqual(plan.segments[1].boundaryReasons, ["transport_boundary"])
        XCTAssertEqual(plan.segments[2].boundaryReasons, ["configuration_boundary"])
        XCTAssertThrowsError(try EEGEDFNominalPlan.inspect(recording: file, store: store, maximumSegments: 2)) {
            XCTAssertEqual($0 as? EEGEDFNominalPlan.Failure, .segmentLimitExceeded)
        }
        XCTAssertThrowsError(try EEGEDFNominalPlan.inspect(recording: file, store: store, maximumSegments: 0)) {
            XCTAssertEqual($0 as? EEGEDFNominalPlan.Failure, .invalidSegmentLimit)
        }
    }

    func testUnstableSamplesRejectEntirePlanInsteadOfBeingDropped() throws {
        let (store, file, root) = try recording(count: 3, before: { i, store in
            if i == 1 { try store.appendEvent(kind: "transport_status", fields: ["status": "recovering"]) }
        })
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try EEGEDFNominalPlan.inspect(recording: file, store: store)) {
            XCTAssertEqual($0 as? EEGEDFNominalPlan.Failure, .unstableTransport)
        }
    }

    func testRepeatedReceiptTimesRemainDistinctNominalSamples() throws {
        let (store, file, root) = try recording(count: 3, sample: { ($0, $0, 0.1, true) })
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = try EEGEDFNominalPlan.inspect(recording: file, store: store)
        XCTAssertEqual(plan.source.repeatedReceiptTimes, 2)
        XCTAssertEqual(plan.segments.count, 1)
        XCTAssertEqual(plan.segments[0].sampleCount, 3)
        XCTAssertEqual(plan.segments[0].firstReceiptSeconds, plan.segments[0].lastReceiptSeconds)
        XCTAssertEqual(plan.segments[0].nominalLastSampleSeconds, 2.0 / 128)
    }
}
