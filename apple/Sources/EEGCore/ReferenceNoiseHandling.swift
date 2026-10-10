import Foundation

/// Static-body comparison orchestration for the noisy-channel runDetection overload.
/// Callers supply channel IDs explicitly. This does not infer noise from EEG or
/// claim that the traced manager caller populates its empty noisy-channel vector.
enum ReferenceNoiseHandling {
    enum Route: Equatable { case unavailable, base, cached, rebuilt, tooManyChannels, buildRejected }
    struct Result<Output> {
        let output: Output?
        let valid: Bool
        let route: Route
    }
    enum Failure: Error { case nonFiniteMetadata }

    /// The fit callback must perform an actual fit or return nil. No channel-mask
    /// algorithm is substituted: the binary calls buildClassifier(profile,false,clone).
    static func run<Payload, Output>(
        base: ReferenceErrorSetCache<Payload>.Entry?, featuresEmpty: Bool,
        storedValidity: Bool, channelMetadata: [Double], noisyChannels: [UInt64],
        actions: [Int32], maximumNoisyChannels: Int32,
        cache: inout ReferenceErrorSetCache<Payload>,
        rebuild: (ReferenceErrorSetCache<Payload>.Entry) throws -> ReferenceErrorSetCache<Payload>.Entry?,
        classify: (Payload) throws -> Output
    ) throws -> Result<Output> {
        guard let base, !featuresEmpty else {
            return Result(output: nil, valid: storedValidity, route: .unavailable)
        }
        guard channelMetadata.allSatisfy(\.isFinite) else { throw Failure.nonFiniteMetadata }
        let intersects = channelMetadata.contains { channel in
            noisyChannels.contains { channel == Double($0) }
        }
        guard intersects else {
            return Result(output: try classify(base.payload), valid: true, route: .base)
        }
        // Lookup precedes the configured limit check. IDs are ordered and duplicates
        // are retained in both the cache key and the vendor vector-length comparison.
        if let entry = try cache.get(actions: actions, channels: noisyChannels) {
            let output = try classify(entry.payload)
            entry.reuseCount &+= 1
            return Result(output: output, valid: true, route: .cached)
        }
        guard Int64(maximumNoisyChannels) >= Int64(noisyChannels.count) else {
            return Result(output: nil, valid: false, route: .tooManyChannels)
        }
        guard let entry = try rebuild(base) else {
            return Result(output: nil, valid: false, route: .buildRejected)
        }
        try cache.put(actions: actions, channels: noisyChannels, entry: entry)
        let output = try classify(entry.payload)
        entry.reuseCount &+= 1
        return Result(output: output, valid: true, route: .rebuilt)
    }
}
