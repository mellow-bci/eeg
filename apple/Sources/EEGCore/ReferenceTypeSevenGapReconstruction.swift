import Foundation

/// Comparison-only composition of recovered temporal interpolation and raw CQ
/// caching for the traced type7/128Hz configuration. Does not assign timestamps,
/// reconstruct unknown package fields, or change live acquisition.
struct ReferenceTypeSevenGapReconstruction {
    enum Failure: Error { case invalidInput }
    struct Sample: Equatable {
        let counter: Int
        /// Extracted numeric values, including the raw CQ column at index7.
        let values: [Double]
    }
    struct Reconstructed: Equatable {
        let counter: Int
        let values: [Double]
        let isInterpolated = true
    }
    struct Result {
        /// nil represents the recovered rejected-distance branch.
        let inserted: [Reconstructed]?
        let measuredCurrent: Sample
    }
    struct Emitted: Equatable {
        let sample: Sample
        let isInterpolated: Bool
    }
    private(set) var previousMeasured: Sample?
    private(set) var lastSuccessfulCallTime = -1.0
    private(set) var rawCQCache = Array(repeating: 0.0, count: 14)
    let maximumCounter: Int

    init(maximumCounter: Int) throws {
        // Counter modulus is an explicit observed/configured input, not guessed
        // from the CQ cycle. Resource bound is our supported-input policy.
        guard (1...65535).contains(maximumCounter) else { throw Failure.invalidInput }
        self.maximumCounter = maximumCounter
    }

    /// Bounded type16 portion of process, excluding signal-strength output and
    /// unknown package metadata. One explicit processing-call time for the batch.
    /// The >0.5s rule resets history only; the CQ cache survives that reset.
    mutating func processEEG(_ samples: [Sample], callTime: Double,
                             maximumPackets: Int) throws -> [Emitted] {
        guard callTime.isFinite, callTime >= 0, maximumPackets > 0,
              samples.count <= maximumPackets else { throw Failure.invalidInput }
        var next = self
        var output: [Emitted] = []
        for sample in samples {
            guard (0...maximumCounter).contains(sample.counter), sample.values.count > 7,
                  sample.values.count <= 70, sample.values.allSatisfy(\.isFinite) else {
                throw Failure.invalidInput
            }
            if callTime - next.lastSuccessfulCallTime > 0.5 { next.previousMeasured = nil }
            if let previous = next.previousMeasured {
                let result = try next.reconstruct(previous: previous, current: sample)
                // Rejected-distance result is empty in the source; it does not
                // advance previous package or last successful call time.
                guard let inserted = result.inserted else { continue }
                output += inserted.map { .init(sample: .init(counter: $0.counter, values: $0.values),
                                                isInterpolated: true) }
            }
            output.append(.init(sample: sample, isInterpolated: false))
            next.previousMeasured = sample
            next.lastSuccessfulCallTime = callTime
        }
        self = next
        return output
    }

    mutating func reconstruct(previous: Sample, current: Sample) throws -> Result {
        guard previous.values.count > 7, previous.values.count <= 70,
              previous.values.count == current.values.count,
              previous.values.allSatisfy(\.isFinite), current.values.allSatisfy(\.isFinite) else {
            throw Failure.invalidInput
        }
        guard let missing = try ReferenceEEGInterpolation.missingCount(
            previousCounter: previous.counter, currentCounter: current.counter,
            maximumCounter: maximumCounter) else {
            return Result(inserted: nil, measuredCurrent: current)
        }
        // 0x101060b48 stores current REAL CQ before filling synthesized samples.
        // Initial entries are +0.0 (constructor resize -> bzero). A rejected
        // distance branches before this store. Atomic error handling is ours.
        var nextCache = rawCQCache
        if let slot = try ReferenceContactQualityRouting.ordinal(counter: Int32(current.counter)) {
            nextCache[slot] = current.values[7]
        }
        var rows = try ReferenceEEGInterpolation.gapValues(
            previous: previous.values, current: current.values, missing: missing)
        var inserted: [Reconstructed] = []
        for i in rows.indices {
            let counter = (previous.counter + i + 1) % (maximumCounter + 1)
            // 0x101060f84 addLastCQ overwrites only counters with a CQ slot;
            // other counters retain the numeric interpolation at this column.
            if let slot = try ReferenceContactQualityRouting.ordinal(counter: Int32(counter)) {
                rows[i][7] = nextCache[slot]
            }
            inserted.append(.init(counter: counter, values: rows[i]))
        }
        rawCQCache = nextCache
        return Result(inserted: inserted, measuredCurrent: current)
    }
}
