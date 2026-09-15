import Foundation

/// Explicit derived-time exchange plan: one EDF+C file per continuity run.
/// This is not a writer, a device-clock reconstruction, or export approval.
/// Original JSONL is required; no samples are padded, interpolated or discarded.
public struct EEGEDFNominalPlan: Sendable {
    public static let timeBasis = "derived_nominal_128hz_per_continuity_run_v1"
    public static let samplesPerSecond = 128
    public let source: EEGEDFReceiptPlan
    public let segments: [Segment]
    public let maximumSegments: Int
    public let exportEnabled = false

    public struct Segment: Sendable, Equatable {
        public let ordinal: Int
        /// Position in the original file's sample sequence, not device counter.
        public let firstSourceSampleOrdinal: Int
        public let sampleCount: Int
        public let firstSampleIndex: Int
        public let lastSampleIndex: Int
        public let firstReceiptSeconds: Double
        public let lastReceiptSeconds: Double
        public let boundaryReasons: [String]
        public let firstWallTimeBounds: ClosedRange<Double>
        public var nominalDurationSeconds: Double { Double(sampleCount) / 128 }
        public var nominalLastSampleSeconds: Double { Double(sampleCount - 1) / 128 }
    }
    public enum Failure: Error, Equatable {
        case invalidSegmentLimit, segmentLimitExceeded, unstableTransport, sourceChanged
    }

    public static func inspect(recording: URL, store: EEGRecordingStore,
                               maximumSegments: Int = 10_000) throws -> Self {
        guard maximumSegments > 0 else { throw Failure.invalidSegmentLimit }
        // Reuse configuration, raw-word mapping, monotonic receipt and clock
        // qualification. Analysis warnings remain attached, not discarded.
        let source = try EEGEDFReceiptPlan.inspect(recording: recording, store: store)
        var segments = [Segment]()
        var pendingReasons: Set<String> = ["recording_start"]
        var stable = false, total = 0, runCount = 0, runStart = 0
        var first: EEGSample?, previous: EEGSample?
        var runReasons = [String]()
        func finishRun() throws {
            guard let first, let previous, runCount > 0 else { return }
            guard segments.count < maximumSegments else { throw Failure.segmentLimitExceeded }
            segments.append(Segment(ordinal: segments.count, firstSourceSampleOrdinal: runStart,
                sampleCount: runCount, firstSampleIndex: first.index, lastSampleIndex: previous.index,
                firstReceiptSeconds: first.receivedAt, lastReceiptSeconds: previous.receivedAt,
                boundaryReasons: runReasons,
                firstWallTimeBounds: try source.clockAnchor.wallTimeBounds(forReceiptSeconds: first.receivedAt)))
        }
        let digest = try store.finalizedRecords(recording: recording) { data, sample in
            try Task.checkCancellation()
            if let sample {
                guard stable else { throw Failure.unstableTransport }
                if let previous {
                    if !sample.continuous { pendingReasons.insert("sample_discontinuity") }
                    if !sample.followsIndexAndCounter(previous) {
                        pendingReasons.insert("index_or_counter_gap")
                    }
                    if sample.receivedAt - previous.receivedAt > 0.5 { pendingReasons.insert("arrival_gap") }
                }
                if first == nil || !pendingReasons.isEmpty {
                    try finishRun()
                    // Bound memory before accepting another segment, including
                    // a one-sample run at the very end of the recording.
                    guard segments.count < maximumSegments else { throw Failure.segmentLimitExceeded }
                    first = sample; runStart = total; runCount = 0
                    runReasons = pendingReasons.sorted(); pendingReasons.removeAll()
                }
                previous = sample; runCount += 1; total += 1
                return
            }
            guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw EEGRecordingError.invalidData
            }
            switch event["kind"] as? String {
            case "transport_status":
                let nextStable = event["status"] as? String == "stable"
                if !nextStable || !stable { pendingReasons.insert("transport_boundary") }
                stable = nextStable
            case "decode_error", "connection_error":
                stable = false; pendingReasons.insert("transport_boundary")
            case "device_metadata": pendingReasons.insert("configuration_boundary")
            default: break
            }
        }
        try finishRun()
        guard digest == source.sourceSHA256, total == source.sampleCount,
              segments.reduce(0, { $0 + $1.sampleCount }) == total else { throw Failure.sourceChanged }
        try Task.checkCancellation()
        return Self(source: source, segments: segments, maximumSegments: maximumSegments)
    }
}
