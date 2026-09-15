import Foundation

/// Preflight for a candidate EDF+D layout, not an EDF writer or export approval.
/// Uses canonical windows only as bounded transport containers; preserves every
/// sample, including invalid/partial analysis windows, with their reasons visible.
public struct EEGEDFReceiptPlan: Sendable {
    public let sourceSHA256: String
    public let sampleCount: Int
    public let channels: [String]
    public let firstReceiptSeconds: Double
    public let lastReceiptSeconds: Double
    public let repeatedReceiptTimes: Int
    public let channelADCRanges: [String: ClosedRange<Int>]
    public let analysisWarnings: [String]
    public let clockAnchor: EEGRecordingClockAnchor
    public let firstWallTimeBounds: ClosedRange<Double>
    public let lastWallTimeBounds: ClosedRange<Double>
    public let samplesPerSignalPerRecord = 1
    public let proposedRecordDurationSeconds = 0
    public let exportEnabled = false
    public enum Failure: Error {
        case missingClockAnchor, emptyRecording, sourceChanged, unsupportedConfiguration
        case invalidADC, decreasingReceiptTime, recordCountOverflow
    }

    public static func inspect(recording: URL, store: EEGRecordingStore) throws -> Self {
        try Task.checkCancellation()
        let clock = try store.clockEvidence(recording: recording)
        guard let anchor = clock.anchor else { throw Failure.missingClockAnchor }
        let channels = EEGRecordingStore.channels
        var count = 0, repeated = 0
        var first: Double?, last: Double?
        var minima = [String: Int](), maxima = [String: Int](), warnings = Set<String>()
        let hash = try store.analysisWindows(recording: recording) { window in
            try Task.checkCancellation()
            guard !window.reasons.contains("unsupported_configuration") else { throw Failure.unsupportedConfiguration }
            guard !window.reasons.contains("invalid_adc") else { throw Failure.invalidADC }
            warnings.formUnion(window.reasons)
            for sample in window.samples {
                // EDF's record-count field is eight printable characters.
                guard count < 99_999_999 else { throw Failure.recordCountOverflow }
                if let last {
                    guard sample.receivedAt >= last else { throw Failure.decreasingReceiptTime }
                    if sample.receivedAt == last { repeated += 1 }
                }
                first = first ?? sample.receivedAt; last = sample.receivedAt; count += 1
                for channel in channels {
                    guard let raw = sample.electrodesADC[channel], raw.isFinite,
                          raw >= 0, raw <= 65535, raw.rounded() == raw else { throw Failure.invalidADC }
                    let value = Int(raw)
                    minima[channel] = min(minima[channel] ?? value, value)
                    maxima[channel] = max(maxima[channel] ?? value, value)
                }
            }
        }
        guard hash == clock.fileSHA256, count == clock.sampleCount else { throw Failure.sourceChanged }
        guard let first, let last, count > 0 else { throw Failure.emptyRecording }
        try Task.checkCancellation()
        return Self(sourceSHA256: hash, sampleCount: count, channels: channels,
            firstReceiptSeconds: first, lastReceiptSeconds: last, repeatedReceiptTimes: repeated,
            channelADCRanges: Dictionary(uniqueKeysWithValues: channels.map { ($0, minima[$0]!...maxima[$0]!) }),
            analysisWarnings: warnings.sorted(), clockAnchor: anchor,
            firstWallTimeBounds: try anchor.wallTimeBounds(forReceiptSeconds: first),
            lastWallTimeBounds: try anchor.wallTimeBounds(forReceiptSeconds: last))
    }

    /// Reversible offset encoding for uncalibrated unsigned ADC, never clamping.
    /// Physical headers, annotation allocation and reader compatibility remain unqualified.
    public static func signedADC(_ word: UInt16) -> Int16 { Int16(Int(word) - 32768) }
}
