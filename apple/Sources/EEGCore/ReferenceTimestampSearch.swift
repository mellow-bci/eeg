/// Bounded SamplesBuffer timestamp search from installed Cortex bodies.
/// Uses immutable, strictly increasing finite positive timestamps. Buffer retention,
/// transport clocks and malformed vendor states are not reproduced.
struct ReferenceTimestampSearch {
    enum Failure: Error { case invalidInput }
    struct Result: Equatable {
        let complete: Bool
        let start: Int64
        let count: Int
    }
    let startIndex: Int64
    let timestamps: [Double]
    var endIndex: Int64 { startIndex + Int64(timestamps.count) }

    init(startIndex: Int64, timestamps: [Double], maximumSamples: Int) throws {
        guard startIndex >= 0, maximumSamples > 0,
              timestamps.count <= maximumSamples,
              startIndex <= Int64.max - Int64(timestamps.count),
              timestamps.allSatisfy({ $0.isFinite && $0 > 0 }),
              zip(timestamps, timestamps.dropFirst()).allSatisfy({ $0 < $1 }) else {
            throw Failure.invalidInput
        }
        self.startIndex = startIndex; self.timestamps = timestamps
    }
    func timestamp(at index: Int64) throws -> Double {
        guard index >= startIndex, index < endIndex else { throw Failure.invalidInput }
        return timestamps[Int(index - startIndex)]
    }
    private func validate(_ from: Double, _ through: Double) throws {
        guard from.isFinite, through.isFinite, from >= 0, through >= from else { throw Failure.invalidInput }
    }
    /// Complete only when the retained tail covers through. A covered interval
    /// inside a timestamp gap is complete with zero samples, not failed search.
    func search(cursor: Int64, from: Double, through: Double) throws -> Result {
        try validate(from, through)
        guard cursor >= 0 else { throw Failure.invalidInput }
        guard let last = timestamps.last, last >= through, last >= from else {
            return .init(complete: false, start: 0, count: 0)
        }
        var first = max(cursor, startIndex)
        while first < endIndex, try timestamp(at: first) < from { first += 1 }
        guard first < endIndex else { return .init(complete: false, start: 0, count: 0) }
        var end = first
        while end < endIndex, try timestamp(at: end) < through { end += 1 }
        if end < endIndex, try timestamp(at: end) == through { end += 1 }
        return .init(complete: true, start: first, count: Int(end - first))
    }
    struct Closest: Equatable { let timestamp: Double; let index: Int64 }
    /// Separate helper, not used for subscription interval selection. Preserves
    /// sentinel returns and direction-dependent ties from the estimated scan.
    func closest(to target: Double) throws -> Closest {
        guard target.isFinite, target >= 0 else { throw Failure.invalidInput }
        guard let first = timestamps.first, let last = timestamps.last else {
            return .init(timestamp: -1, index: -1)
        }
        if target < first { return .init(timestamp: -2, index: -1) }
        if target > last { return .init(timestamp: -1, index: -1) }
        if first == last { return .init(timestamp: first, index: startIndex) }
        // Body uses count, not count-1, then signed truncation and clamping.
        let estimate = (target - first) / (last - first) * Double(timestamps.count)
        var index = min(timestamps.count - 1, max(0, Int(estimate.rounded(.towardZero))))
        let descending = timestamps[index] > target
        if descending {
            while index > 0, timestamps[index] > target { index -= 1 }
            let upper = min(index + 1, timestamps.count - 1)
            if abs(target - timestamps[index]) >= abs(target - timestamps[upper]) { index = upper }
        } else {
            while index < timestamps.count - 1, timestamps[index] < target { index += 1 }
            let lower = max(0, index - 1)
            if abs(target - timestamps[index]) >= abs(target - timestamps[lower]) { index = lower }
        }
        return .init(timestamp: timestamps[index], index: startIndex + Int64(index))
    }
    /// samplesBetweenTimestamps fallback clips to available measurements; it
    /// does not interpolate or demand coverage of the interval's right edge.
    func clipped(from: Double, through: Double) throws -> Result {
        try validate(from, through)
        var first = startIndex
        while first < endIndex, try timestamp(at: first) < from { first += 1 }
        guard first < endIndex, try timestamp(at: first) <= through else {
            return .init(complete: false, start: 0, count: 0)
        }
        var end = first
        while end < endIndex, try timestamp(at: end) <= through { end += 1 }
        return .init(complete: false, start: first, count: Int(end - first))
    }
}

/// searchData plus readData's per-stream index cache/slice choices. Primary
/// timestamps and index scheduler remain canonical; no independent timer.
struct ReferenceTimestampRouting {
    enum Failure: Error { case invalidInput }
    struct Selection: Equatable {
        let stream: Int
        let search: ReferenceTimestampSearch.Result
        let usedClippedFallback: Bool
    }
    private(set) var cachedStarts: [Int: Int64] = [:]
    mutating func route(primaryStream: Int, streamOrder: [Int],
                        buffers: [Int: ReferenceTimestampSearch], from: Double,
                        through: Double, permissive: Bool) throws -> [Selection]? {
        guard streamOrder.count <= 64, Set(streamOrder).count == streamOrder.count,
              streamOrder.contains(primaryStream), buffers[primaryStream] != nil,
              streamOrder.allSatisfy({ buffers[$0] != nil }) else { throw Failure.invalidInput }
        // Search all secondary streams first. Ordinary failure does not publish
        // slices or change readData's cache. Permissive fallback is explicit.
        var found: [(Int, ReferenceTimestampSearch.Result)] = []
        for id in streamOrder where id != primaryStream {
            let r = try buffers[id]!.search(cursor: cachedStarts[id] ?? 0, from: from, through: through)
            if !r.complete && !permissive { return nil }
            found.append((id, r))
        }
        var selections: [Selection] = []
        for (id, r) in found {
            if r.complete {
                cachedStarts[id] = r.start // Cache start, not start + count.
                selections.append(.init(stream: id, search: r, usedClippedFallback: false))
            } else {
                selections.append(.init(stream: id, search: try buffers[id]!.clipped(from: from, through: through),
                                        usedClippedFallback: true))
            }
        }
        return selections
    }
}
