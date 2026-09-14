import Foundation
import XCTest
@testable import EEGCore

final class AnalysisWindowTests: XCTestCase {
    private func sample(_ i: Int) -> EEGSample {
        EEGSample(index: i, counter: i % 128, receivedAt: Double(i) / 128, continuous: true,
            adcWords: [UInt16](repeating: 31200, count: 15),
            electrodesADC: Dictionary(uniqueKeysWithValues: EEGRecordingStore.channels.map { ($0, 31200.0) }),
            electrodesMicrovolts: Dictionary(uniqueKeysWithValues: EEGRecordingStore.channels.map { ($0, 4000.0) }),
            notificationSlot: 0, recordFlag: 0)
    }
    private func event(_ fields: [String: String]) throws -> Data { try JSONSerialization.data(withJSONObject: fields) }
    private func ready() throws -> EEGAnalysisWindowAssembler {
        var a = EEGAnalysisWindowAssembler()
        try a.event(event(["kind": "device_metadata", "81072f44-9f3d-11e3-a9dc-0002a5d5c51b": "018000102010"]))
        try a.event(event(["kind": "transport_status", "status": "stable"]))
        return a
    }
    func testKnownContextCreatesNonoverlappingWindowsAndRejectsTail() throws {
        var a = try ready(); var windows = [EEGAnalysisWindow]()
        for i in 0..<513 { if let window = a.append(sample(i)) { windows.append(window) } }
        windows.append(a.finish()!)
        XCTAssertEqual(windows.map(\.ordinal), [0, 1, 2])
        XCTAssertTrue(windows[0].valid); XCTAssertTrue(windows[1].valid)
        XCTAssertEqual(windows[1].samples.first?.index, 256)
        XCTAssertEqual(windows[2].reasons, ["partial_window"])
    }
    func testMissingMetadataNeverBecomesReady() {
        var a = EEGAnalysisWindowAssembler(); var result: EEGAnalysisWindow?
        for i in 0..<256 { result = a.append(sample(i)) }
        XCTAssertFalse(result!.valid)
        XCTAssertTrue(result!.reasons.contains("transport_unstable"))
        XCTAssertTrue(result!.reasons.contains("unsupported_configuration"))
    }
    func testRecoveryWithinWindowAndBoundaryGapAreRejected() throws {
        var a = try ready()
        for i in 0..<128 { _ = a.append(sample(i)) }
        try a.event(event(["kind": "transport_status", "status": "recovering"]))
        _ = a.append(sample(128))
        try a.event(event(["kind": "transport_status", "status": "stable"]))
        var result: EEGAnalysisWindow?
        for i in 129..<256 { result = a.append(sample(i)) }
        XCTAssertTrue(result!.reasons.contains("source_or_segment_boundary"))
        XCTAssertTrue(result!.reasons.contains("transport_unstable"))
        for i in 257..<513 { result = a.append(sample(i)) }
        XCTAssertTrue(result!.reasons.contains("index_or_counter_gap"))
    }
    func testFinalSummaryRequiredByRecordingAnalysis() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EEGRecordingStore(directory: directory)
        let url = try store.start()
        try store.append(sample: sample(0))
        XCTAssertThrowsError(try store.analysisWindows(recording: url) { _ in })
        try store.finish()
        var count = 0
        try store.analysisWindows(recording: url) { window in count += 1; XCTAssertFalse(window.valid) }
        XCTAssertEqual(count, 1)
    }
    func testFinalizedRecordingUsesMetadataAndRejectsOutsidePath() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EEGRecordingStore(directory: directory)
        let url = try store.start()
        try store.appendEvent(kind: "device_metadata", fields: ["81072f44-9f3d-11e3-a9dc-0002a5d5c51b": "018000102010"])
        try store.appendEvent(kind: "transport_status", fields: ["status": "stable"])
        for i in 0..<256 { try store.append(sample: sample(i)) }
        try store.finish()
        var windows = [EEGAnalysisWindow]()
        try store.analysisWindows(recording: url) { windows.append($0) }
        XCTAssertEqual(windows.count, 1)
        XCTAssertTrue(windows[0].valid)
        XCTAssertThrowsError(try store.analysisWindows(recording: directory.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent)) { _ in })
    }

    func testConcurrentSourceChangesRejectProvisionalAnalysis() throws {
        for mutation in ["append", "rewrite", "replace"] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = try EEGRecordingStore(directory: directory)
            let url = try store.start()
            for i in 0..<512 { try store.append(sample: sample(i)) }
            try store.finish()
            let original = try Data(contentsOf: url)
            var changed = false
            XCTAssertThrowsError(try store.analysisWindows(recording: url) { _ in
                guard !changed else { return }; changed = true
                switch mutation {
                case "append":
                    let file = try FileHandle(forWritingTo: url)
                    defer { try? file.close() }
                    try file.seekToEnd(); try file.write(contentsOf: Data(" ".utf8)); try file.synchronize()
                case "rewrite":
                    // Rewrite bytes already read without changing length. Ensure a
                    // distinct mtime even on filesystems with coarse timestamps.
                    let file = try FileHandle(forWritingTo: url)
                    defer { try? file.close() }
                    try file.write(contentsOf: Data(" ".utf8)); try file.synchronize()
                    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: url.path)
                default:
                    // Identical bytes under a new inode still invalidate path identity.
                    try original.write(to: url, options: .atomic)
                }
            }) { error in
                XCTAssertEqual(error as? EEGRecordingError, .sourceChanged, mutation)
            }
            XCTAssertTrue(changed)
        }
    }

}
