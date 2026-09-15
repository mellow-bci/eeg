import XCTest
import CryptoKit
@testable import EEGCore

final class EDFNominalExportTests: XCTestCase {
    private enum Injected: Error { case write, synchronize, close, cancellation, cleanup }
    private final class FaultOutput: EEGRecordingOutput {
        let real: EEGFileRecordingOutput
        let failure: Injected
        let writeCall: Int
        var writes = 0
        init(_ file: FileHandle, failure: Injected, writeCall: Int = 2) {
            real = EEGFileRecordingOutput(file); self.failure = failure; self.writeCall = writeCall
        }
        func write(_ data: Data) throws {
            writes += 1
            if writes == writeCall && (failure == .write || failure == .cancellation) {
                try real.write(Data(data.prefix(3))) // A real partial output exists.
                if failure == .cancellation { throw CancellationError() }
                throw failure
            }
            try real.write(data)
        }
        func synchronize() throws {
            if failure == .synchronize { throw failure }
            try real.synchronize()
        }
        func close() throws {
            try real.close()
            if failure == .close { throw failure }
        }
        func offset() throws -> UInt64 { try real.offset() }
        func truncate(at offset: UInt64) throws { try real.truncate(at: offset) }
    }
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

    func testOutputFailuresNeverLeaveSuccessfulPackagesOrModifySource() throws {
        let (store, source, root, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try Data(contentsOf: source)
        // First EDF's partial write, synchronization, close and cancellation;
        // then receipt partial write, after both EDF files have completed.
        let cases: [(Injected, Int, Int)] = [(.write, 1, 2), (.synchronize, 1, 2),
            (.close, 1, 2), (.cancellation, 1, 2), (.write, 3, 1), (.synchronize, 3, 1), (.close, 3, 1)]
        for (index, test) in cases.enumerated() {
            let target = root.appendingPathComponent("failure-\(index)")
            var files = 0
            XCTAssertThrowsError(try EEGEDFNominalExport.write(recording: source, store: store, to: target,
                outputFactory: { handle in
                    files += 1
                    return files == test.1 ? FaultOutput(handle, failure: test.0, writeCall: test.2) : EEGFileRecordingOutput(handle)
                }, removePackage: { try FileManager.default.removeItem(at: $0) })) { error in
                    if test.0 == .cancellation { XCTAssertTrue(error is CancellationError) }
                    else { XCTAssertEqual(error as? Injected, test.0) }
                }
            XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
            XCTAssertEqual(try Data(contentsOf: source), original)
        }
    }

    func testCleanupFailureRetainsBothErrorsAndIdentifiesPartialPackage() throws {
        let (store, source, root, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try Data(contentsOf: source)
        let target = root.appendingPathComponent("partial")
        XCTAssertThrowsError(try EEGEDFNominalExport.write(recording: source, store: store, to: target,
            outputFactory: { FaultOutput($0, failure: .write) },
            removePackage: { _ in throw Injected.cleanup })) { error in
                let failure = error as? EEGEDFNominalExport.CleanupFailure
                XCTAssertEqual(failure?.original, "write")
                XCTAssertEqual(failure?.cleanup, "cleanup")
                XCTAssertEqual(failure?.packagePath, target.path)
                XCTAssertTrue(error.localizedDescription.contains("not a completed export"))
            }
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("provenance.json").path))
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("segment-000001.edf")).count, 4099)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testReceiptSyncOrCloseFailureCannotPublishCompletionEvenWhenCleanupFails() throws {
        let (store, source, root, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for failure in [Injected.synchronize, .close] {
            let target = root.appendingPathComponent(String(describing: failure))
            var files = 0
            XCTAssertThrowsError(try EEGEDFNominalExport.write(recording: source, store: store, to: target,
                outputFactory: { handle in
                    files += 1
                    return files == 3 ? FaultOutput(handle, failure: failure) : EEGFileRecordingOutput(handle)
                }, removePackage: { _ in throw Injected.cleanup })) { error in
                    XCTAssertEqual((error as? EEGEDFNominalExport.CleanupFailure)?.original, String(describing: failure))
                }
            XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("provenance.json").path))
            // Even a fully parseable receipt remains explicitly pending until
            // sync and close succeed; its presence must not signal completion.
            let pending = try Data(contentsOf: target.appendingPathComponent(".provenance.pending"))
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: pending))
        }
    }
}
