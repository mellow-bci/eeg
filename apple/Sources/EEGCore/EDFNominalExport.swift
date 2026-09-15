import Foundation
import Darwin
import CryptoKit

/// Experimental exchange writer. No app format option or hardware qualification.
/// Completion requires provenance.json; any failure removes this newly owned bundle.
public enum EEGEDFNominalExport {
    public enum Failure: Error { case destinationExists, invalidDestination, unsupportedDate, headerField, annotationOverflow, sourceChanged }
    public struct CleanupFailure: Error, LocalizedError {
        public let original: String
        public let cleanup: String
        public let packagePath: String
        public var errorDescription: String? {
            "EDF export failed: \(original). Removing the partial package also failed: \(cleanup). Inspect \(packagePath); it is not a completed export."
        }
    }

    public static func write(recording: URL, store: EEGRecordingStore, to destination: URL,
                             maximumSegments: Int = 10_000) throws {
        try write(recording: recording, store: store, to: destination, maximumSegments: maximumSegments,
            outputFactory: { EEGFileRecordingOutput($0) },
            removePackage: { try FileManager.default.removeItem(at: $0) })
    }

    /// Per-call I/O seams for deterministic failures; production always uses
    /// exclusively opened real files, never a synthetic acquisition path.
    static func write(recording: URL, store: EEGRecordingStore, to destination: URL,
                      maximumSegments: Int = 10_000,
                      outputFactory: (FileHandle) -> EEGRecordingOutput,
                      removePackage: (URL) throws -> Void) throws {
        try Task.checkCancellation()
        guard destination.isFileURL else { throw Failure.invalidDestination }
        let initial = try EEGEDFNominalPlan.inspect(recording: recording, store: store, maximumSegments: maximumSegments)
        // mkdir, unlike createDirectory, refuses an already existing directory.
        guard mkdir(destination.path, 0o700) == 0 else {
            if errno == EEXIST { throw Failure.destinationExists }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        do {
            try writeContents(recording: recording, store: store, to: destination,
                initial: initial, maximumSegments: maximumSegments, outputFactory: outputFactory)
        } catch {
            let original = error
            do { try removePackage(destination) }
            catch {
                throw CleanupFailure(original: String(describing: original), cleanup: String(describing: error),
                                     packagePath: destination.path)
            }
            throw original
        }
    }

    private static func writeContents(recording: URL, store: EEGRecordingStore, to destination: URL,
                                      initial: EEGEDFNominalPlan, maximumSegments: Int,
                                      outputFactory: (FileHandle) -> EEGRecordingOutput) throws {
        let native = destination.appendingPathComponent(recording.lastPathComponent)
        try store.exportNative(recording: recording, to: native)
        let copiedStore = try EEGRecordingStore(directory: destination)
        let plan = try EEGEDFNominalPlan.inspect(recording: native, store: copiedStore, maximumSegments: maximumSegments)
        guard plan.source.sourceSHA256 == initial.source.sourceSHA256 else { throw Failure.sourceChanged }
        var file: EEGRecordingOutput?, fileHash = SHA256(), bytes = 0, sampleOrdinal = 0, segmentOrdinal = 0
        var results = [[String: Any]]()
        defer { try? file?.close() }
        func writeBytes(_ data: Data) throws {
            guard let file else { throw Failure.sourceChanged }
            try file.write(data); fileHash.update(data: data); bytes += data.count
        }
        let digest = try copiedStore.finalizedRecords(recording: native) { _, sample in
            try Task.checkCancellation()
            guard let sample else { return }
            guard segmentOrdinal < plan.segments.count else { throw Failure.sourceChanged }
            let segment = plan.segments[segmentOrdinal]
            let localIndex = sampleOrdinal - segment.firstSourceSampleOrdinal
            guard (0..<segment.sampleCount).contains(localIndex) else { throw Failure.sourceChanged }
            let selectedWallTime = segment.firstWallTimeBounds.lowerBound
            let headerOrigin = floor(selectedWallTime)
            let firstOffset = selectedWallTime - headerOrigin
            let name = String(format: "segment-%06d.edf", segmentOrdinal + 1)
            if localIndex == 0 {
                file = outputFactory(try exclusiveFile(destination.appendingPathComponent(name)))
                fileHash = SHA256(); bytes = 0
                try writeBytes(header(segment: segment, origin: headerOrigin,
                    utcOffset: plan.source.clockAnchor.localUTCOffsetSeconds))
            }
            var record = Data()
            for channel in plan.source.channels {
                guard let value = sample.electrodesADC[channel], value >= 0, value <= 65535,
                      value.rounded() == value else { throw Failure.sourceChanged }
                let bits = UInt16(bitPattern: EEGEDFReceiptPlan.signedADC(UInt16(value)))
                record.append(UInt8(bits & 255)); record.append(UInt8(bits >> 8))
            }
            let onset = String(format: "%+.8f", locale: Locale(identifier: "en_US_POSIX"), firstOffset + Double(localIndex) / 128)
            var tal = Data((onset + "\u{14}\u{14}\0").utf8)
            if localIndex == 0 {
                tal.append(Data((onset + "\u{14}Derived nominal 128 Hz; see provenance.json\u{14}\0").utf8))
            }
            guard tal.count <= 128 else { throw Failure.annotationOverflow }
            record.append(tal); record.append(Data(repeating: 0, count: 128 - tal.count))
            try writeBytes(record)
            sampleOrdinal += 1
            if localIndex + 1 == segment.sampleCount {
                try file?.synchronize(); try file?.close(); file = nil
                results.append([
                    "file": name, "sha256": fileHash.finalize().map { String(format: "%02x", $0) }.joined(), "bytes": bytes,
                    "first_source_sample_ordinal": segment.firstSourceSampleOrdinal, "sample_count": segment.sampleCount,
                    "first_sample_index": segment.firstSampleIndex, "last_sample_index": segment.lastSampleIndex,
                    "first_receipt_seconds": segment.firstReceiptSeconds, "last_receipt_seconds": segment.lastReceiptSeconds,
                    "first_wall_time_bounds": [segment.firstWallTimeBounds.lowerBound, segment.firstWallTimeBounds.upperBound],
                    "selected_nominal_start_unix_seconds": selectedWallTime, "header_origin_unix_seconds": headerOrigin,
                    "first_record_onset_seconds": firstOffset, "nominal_duration_seconds": segment.nominalDurationSeconds,
                    "boundary_reasons": segment.boundaryReasons
                ])
                segmentOrdinal += 1
            }
        }
        guard digest == plan.source.sourceSHA256, sampleOrdinal == plan.source.sampleCount,
              segmentOrdinal == plan.segments.count, file == nil else { throw Failure.sourceChanged }
        let receipt: [String: Any] = [
            "schema": "eeg.edf-nominal-exchange.v1", "time_basis": EEGEDFNominalPlan.timeBasis,
            "source_file": native.lastPathComponent, "source_sha256": digest, "sample_count": sampleOrdinal,
            "channels": plan.source.channels, "units": "uncalibrated_unsigned_adc", "samples_per_second": 128,
            "maximum_segments": maximumSegments, "segments": results, "analysis_warnings": plan.source.analysisWarnings,
            "writer_implementation": ["schema": EEGSourceIdentity.schema, "sha256": EEGSourceIdentity.sha256,
                "input_file_count": EEGSourceIdentity.inputFileCount],
            "clock_anchor": try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan.source.clockAnchor)),
            "hardware_validated": false, "reader_qualified": false,
            "definitions": [
                "timing": "Derived nominal axis per segment. Start uses the lower conditional wall-time bound at first receipt, not measured neural acquisition time. Header uses its whole-second floor; TAL carries the fraction rounded to eight decimal places.",
                "clock": "Receipt bracket retained. Wall-clock synchronization, Bluetooth delay and relative clock drift are unmeasured.",
                "samples": "Every original sample appears once, in file order. Signed EDF word equals unsigned ADC minus 32768. Blank physical dimension; physical range 0...65535. No microvolt calibration, filtering, padding or interpolation.",
                "events": "Original JSONL is mandatory and preserves all events and measured receipt times. EDF contains timekeeping and a derived-timeline notice only; native markers/trials are not retimed or copied as EDF annotations.",
                "scope": "Experimental writer. Separate segments must not be concatenated as continuous data. Not clinical or physiological qualification."
            ]
        ]
        try Task.checkCancellation()
        let pending = destination.appendingPathComponent(".provenance.pending")
        let output = outputFactory(try exclusiveFile(pending))
        defer { try? output.close() }
        try output.write(JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys, .prettyPrinted]))
        try output.synchronize(); try output.close()
        // Do not expose a completion marker before receipt I/O succeeds. Same-
        // directory exclusive rename is atomic; unsupported filesystems fail.
        guard renameatx_np(AT_FDCWD, pending.path, AT_FDCWD,
                           destination.appendingPathComponent("provenance.json").path, UInt32(RENAME_EXCL)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func exclusiveFile(_ url: URL) throws -> FileHandle {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    private static func header(segment: EEGEDFNominalPlan.Segment, origin: Double, utcOffset: Int) throws -> Data {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSince1970: origin + Double(utcOffset)))
        guard let year = parts.year, (1985...2084).contains(year), let month = parts.month,
              let day = parts.day, let hour = parts.hour, let minute = parts.minute, let second = parts.second else { throw Failure.unsupportedDate }
        let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
        var data = Data()
        func field(_ value: String, _ width: Int) throws {
            let bytes = Array(value.utf8)
            guard bytes.count <= width, bytes.allSatisfy({ (32...126).contains($0) }) else { throw Failure.headerField }
            data.append(contentsOf: bytes); data.append(Data(repeating: 32, count: width - bytes.count))
        }
        for (text, width) in [("0", 8), ("X X X X", 80),
            (String(format: "Startdate %02d-%@-%04d X X EPOC_X", day, months[month - 1], year), 80),
            (String(format: "%02d.%02d.%02d", day, month, year % 100), 8),
            (String(format: "%02d.%02d.%02d", hour, minute, second), 8),
            ("4096", 8), ("EDF+C", 44), (String(segment.sampleCount), 8), (".0078125", 8), ("15", 4)] {
            try field(text, width)
        }
        let ordinary = EEGRecordingStore.channels.map { "EEG " + $0 }
        let groups: [([String], Int)] = [
            (ordinary + ["EDF Annotations"], 16), (Array(repeating: "", count: 15), 80),
            (Array(repeating: "", count: 15), 8), (Array(repeating: "0", count: 14) + ["-1"], 8),
            (Array(repeating: "65535", count: 14) + ["1"], 8),
            (Array(repeating: "-32768", count: 15), 8), (Array(repeating: "32767", count: 15), 8),
            (Array(repeating: "", count: 15), 80), (Array(repeating: "1", count: 14) + ["64"], 8),
            (Array(repeating: "", count: 15), 32)
        ]
        for (values, width) in groups { for value in values { try field(value, width) } }
        guard data.count == 4096 else { throw Failure.headerField }
        return data
    }
}
