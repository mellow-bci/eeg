import Foundation

/// A host-clock observation, not a device clock or a claim of UTC accuracy.
public struct EEGRecordingClockAnchor: Encodable, Sendable {
    public let schema = "eeg.recording-clock-anchor.v1"
    public let timeBasis = "recorded_receipt_seconds"
    public let wallClockAccuracy = "unmeasured"
    public let receiptBefore: Double
    public let receiptAfter: Double
    public let wallUnixSeconds: Double
    public let localUTCOffsetSeconds: Int
    public enum Failure: Error { case invalidObservation }

    public init(receiptBefore: Double, receiptAfter: Double, wallUnixSeconds: Double,
                localUTCOffsetSeconds: Int) throws {
        guard receiptBefore.isFinite, receiptAfter.isFinite, wallUnixSeconds.isFinite,
              receiptBefore >= 0, receiptAfter >= receiptBefore,
              (-86400...86400).contains(localUTCOffsetSeconds) else { throw Failure.invalidObservation }
        self.receiptBefore = receiptBefore; self.receiptAfter = receiptAfter
        self.wallUnixSeconds = wallUnixSeconds; self.localUTCOffsetSeconds = localUTCOffsetSeconds
    }
    /// Brackets the wall-clock call. Does not hide scheduling delay in a midpoint.
    public static func capture(receiptClock: () -> Double, wallClock: () -> Date = { Date() },
                               timeZone: TimeZone = .current) throws -> EEGRecordingClockAnchor {
        let before = receiptClock()
        let wall = wallClock()
        let after = receiptClock()
        return try EEGRecordingClockAnchor(receiptBefore: before, receiptAfter: after,
            wallUnixSeconds: wall.timeIntervalSince1970, localUTCOffsetSeconds: timeZone.secondsFromGMT(for: wall))
    }
    /// Conditional mapping only: assumes no clock adjustment or relative clock drift.
    /// The bounds include call-order uncertainty, not wall-clock synchronization error.
    public func wallTimeBounds(forReceiptSeconds value: Double) throws -> ClosedRange<Double> {
        let lower = wallUnixSeconds + (value - receiptAfter)
        let upper = wallUnixSeconds + (value - receiptBefore)
        guard value.isFinite, value >= 0, lower.isFinite, upper.isFinite else { throw Failure.invalidObservation }
        return lower...upper
    }
}
