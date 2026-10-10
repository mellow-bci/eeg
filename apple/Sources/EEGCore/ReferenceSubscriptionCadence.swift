/// Bounded index scheduler from SynchronisedSubscription::init/readData/processNewData.
/// Timestamp search and cross-stream slicing remain supplied operations. This is
/// not a wall-clock timer, BLE scheduler or replacement for acquisition.
struct ReferenceSubscriptionCadence {
    enum Failure: Error { case invalidInput, capacityExceeded }
    struct Request: Equatable {
        let start: Int64
        let endExclusive: Int64
        let dropped: Int64
        let mayClipSearch: Bool
    }
    let windowSamples: Int64
    let stepSamples: Int64
    private(set) var cursor: Int64

    init(sampleRate: Double, windowSeconds: Double, stepSeconds: Double,
         startIndex: Int64) throws {
        let window = sampleRate * windowSeconds, step = sampleRate * stepSeconds
        guard sampleRate.isFinite, sampleRate > 0, windowSeconds.isFinite,
              stepSeconds.isFinite, stepSeconds > 0, windowSeconds >= stepSeconds,
              window.isFinite, step.isFinite, window >= 1, step >= 1,
              window <= Double(Int32.max), step <= Double(Int32.max), startIndex >= 0 else {
            throw Failure.invalidInput
        }
        // Signed FCVTZS in subscription init; positive supported domain truncates.
        windowSamples = Int64(window.rounded(.towardZero))
        stepSamples = Int64(step.rounded(.towardZero)); cursor = startIndex
    }

    /// One read. A dropped-buffer cursor is advanced even if the search fails,
    /// matching readData; successful search advances by the configured step.
    mutating func read(startIndex: Int64, endIndex: Int64, force: Bool,
                       isAlmostFull: Bool, search: (Request) throws -> Bool) throws -> Request? {
        guard startIndex >= 0, endIndex >= startIndex else { throw Failure.invalidInput }
        let previous = cursor
        let next = max(cursor, startIndex)
        guard next <= Int64.max - windowSamples else { throw Failure.invalidInput }
        cursor = next
        guard next + windowSamples <= endIndex else { return nil }
        let request = Request(start: next, endExclusive: next + windowSamples,
            dropped: max(0, startIndex - previous),
            mayClipSearch: force || (next - startIndex < 100 && isAlmostFull))
        guard try search(request) else { return nil }
        guard next <= Int64.max - stepSamples else { throw Failure.invalidInput }
        cursor = next + stepSamples
        return request
    }

    /// processNewData drains successful nonempty read results, unlike the inner
    /// manager's one-epoch invocation. The call bound is our explicit support cap.
    mutating func process(startIndex: Int64, endIndex: Int64, isAlmostFull: Bool,
                          maximumReads: Int, search: (Request) throws -> Bool) throws -> [Request] {
        guard maximumReads > 0 else { throw Failure.invalidInput }
        var results: [Request] = []
        while results.count < maximumReads {
            guard let value = try read(startIndex: startIndex, endIndex: endIndex,
                                       force: false, isAlmostFull: isAlmostFull, search: search) else { return results }
            results.append(value)
        }
        guard cursor > endIndex || windowSamples > endIndex - cursor else { throw Failure.capacityExceeded }
        return results
    }
}
