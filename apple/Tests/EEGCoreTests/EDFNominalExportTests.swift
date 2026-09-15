import XCTest
import CryptoKit
@testable import EEGCore

final class EDFNominalExportTests: XCTestCase {
    private func fixture(wall: Double = 1_800_000_000) throws -> (EEGRecordingStore, URL, URL, [[Int]]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try EEGRecordingStore(directory: root.appendingPathComponent("source")), file = try store.start()
        let anchor = try EEGRecordingClockAnchor(receiptBefore: 0, receiptAfter: 0.01,
            wallUnixSeconds: wall, localUTCOffsetSeconds: 19800)
        try store.appendEvent(kind: "recording_clock_anchor", fields: ["json": String(decoding: JSONEncoder().encode(anchor), as: UTF8.self)])
        try store.appendEvent(kind: "device_metadata", fields: ["81072f44-9f3d-11e3-a9dc-0002a5d5c51b": "018000102010"])
        try store.appendEvent(kind: "transport_status", fields: ["status": "stable"])
        try store.appendEvent(kind: "marker", fields: ["text": "日本語 preserved only in native source", "received_at": "0.025"])
        var expected = [[Int]]()
        for i in 0..<263 {
            let words = (0..<15).map { word in UInt16(i == 0 ? 0 : i == 1 ? 65535 : (i * 251 + word * 4001) % 65536) }
            let adc = Dictionary(uniqueKeysWithValues: EPOCProtocol.electrodeWords.map { ($0.name, Double(words[$0.index])) })
            expected.append(EEGRecordingStore.channels.map { Int(adc[$0]!) })
            try store.append(sample: EEGSample(index: i, counter: i % 128,
                receivedAt: 0.02 + Double(i) / 128 + (i >= 129 ? 1 : 0), continuous: i != 129,
                adcWords: words, electrodesADC: adc, electrodesMicrovolts: nil, notificationSlot: 0, recordFlag: 0))
        }
        try store.finish()
        return (store, file, root, expected)
    }

    func testNativePackagePreservesAllWordsSourceAndProvenance() throws {
        let (store, source, root, expected) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try Data(contentsOf: source)
        let target = root.appendingPathComponent("exchange")
        try EEGEDFNominalExport.write(recording: source, store: store, to: target)
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent(source.lastPathComponent)), original)
        let data = try Data(contentsOf: target.appendingPathComponent("provenance.json"))
        let receipt = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(receipt["source_sha256"] as? String, SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined())
        XCTAssertEqual(receipt["sample_count"] as? Int, 263)
        XCTAssertEqual(receipt["hardware_validated"] as? Bool, false)
        let segments = try XCTUnwrap(receipt["segments"] as? [[String: Any]])
        XCTAssertEqual(segments.count, 2)
        var recovered = [[Int]]()
        for (ordinal, segment) in segments.enumerated() {
            let count = ordinal == 0 ? 129 : 134
            XCTAssertEqual(segment["sample_count"] as? Int, count)
            let name = try XCTUnwrap(segment["file"] as? String)
            let bytes = try Data(contentsOf: target.appendingPathComponent(name))
            XCTAssertEqual(bytes.count, 4096 + 156 * count)
            XCTAssertEqual(segment["sha256"] as? String, SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
            XCTAssertEqual(String(decoding: bytes[244..<252], as: UTF8.self), ".0078125")
            for i in 0..<count {
                recovered.append((0..<14).map { channel in
                    let offset = 4096 + i * 156 + channel * 2
                    return Int(Int16(bitPattern: UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8)) + 32768
                })
            }
            let permissions = try FileManager.default.attributesOfItem(atPath: target.appendingPathComponent(name).path)[.posixPermissions] as? NSNumber
            XCTAssertEqual(permissions?.intValue, 0o600)
        }
        XCTAssertEqual(recovered, expected)
        let again = root.appendingPathComponent("repeat")
        try EEGEDFNominalExport.write(recording: source, store: store, to: again)
        for name in try FileManager.default.contentsOfDirectory(atPath: target.path) {
            XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent(name)), try Data(contentsOf: again.appendingPathComponent(name)))
        }
        // Optional reproducible native output for the independent reader probe.
        // Requires a NEW destination; no app library or headset is accessed.
        if let path = ProcessInfo.processInfo.environment["EEG_EDF_FIXTURE"] {
            let output = URL(fileURLWithPath: path)
            try EEGEDFNominalExport.write(recording: source, store: store, to: output)
            let truth: [String: Any] = ["synthetic": true, "raw_samples": expected,
                "segment_counts": [129, 134], "first_receipt_seconds": [0.02, 0.02 + 129.0 / 128 + 1],
                "wall_unix_seconds": 1_800_000_000, "receipt_after": 0.01, "utc_offset_seconds": 19800]
            try JSONSerialization.data(withJSONObject: truth, options: [.sortedKeys]).write(to: output.appendingPathComponent("qualification-input.json"))
        }
    }

    func testRefusesExistingDestinationAndCleansFailedPackage() throws {
        let (store, source, root, _) = try fixture(wall: 0) // 1970 is outside supported header dates.
        defer { try? FileManager.default.removeItem(at: root) }
        let failed = root.appendingPathComponent("failed")
        XCTAssertThrowsError(try EEGEDFNominalExport.write(recording: source, store: store, to: failed))
        XCTAssertFalse(FileManager.default.fileExists(atPath: failed.path))
        let existing = root.appendingPathComponent("existing")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: false)
        let sentinel = existing.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sentinel)
        XCTAssertThrowsError(try EEGEDFNominalExport.write(recording: source, store: store, to: existing))
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep".utf8))
    }
}
