import Foundation

/// Manager front-end call cadence only: one detector call -> one filtered append
/// and at most one stream removal. This is NOT a timer or sample-arrival driver.
/// Evidence: manager-cadence-continuation-20261011; no live pipeline integration.
struct ReferenceManagerCadence {
    enum Failure: Error { case invalidConfiguration, invalidInput }
    struct Configuration {
        let sampleRate: Int
        let windowSeconds: Double
        let stepSeconds: Double
        let selectedChannelCount: Int
        let maximumBufferedSamples: Int
        let maximumSamplesPerBlock: Int
    }
    struct Control {
        let classifierEmpty: Bool
        /// Manager +0xf0, supplied by caller; no profile mutation is inferred.
        let autoSamplingNeutral: Bool
        let trainingControl: Int
    }
    enum Route: Equatable { case waiting, consumedWithoutFeatures, extractFeatures }
    struct Tick {
        let route: Route
        let filteredBlock: [[Double]]
        /// Preserved even when the manager discards this epoch without features.
        let consumedEpoch: [[Double]]?
        /// Manager subsequently invokes sampling/training with empty matrices
        /// when this is nil. Those controls are not silently skipped here.
        var featureInput: [[Double]]? { route == .extractFeatures ? consumedEpoch : nil }
    }
    struct StopEffects: Equatable {
        let resetTrainingState: Bool
        let clearBackgroundMatrix: Bool
        let inputFilterReset: Bool
    }
    private(set) var configuration: Configuration
    private var filter: ReferenceDeployedFilter
    private var stream: ReferenceEpochStream
    var windowSamples: Int { stream.windowSamples }
    var stepSamples: Int { stream.stepSamples }
    var bufferedSamples: Int { stream.bufferedSamples }

    init(configuration: Configuration) throws {
        guard configuration.selectedChannelCount > 0, configuration.selectedChannelCount <= 70 else {
            throw Failure.invalidConfiguration
        }
        self.configuration = configuration
        filter = try .deployed(maximumChannels: configuration.selectedChannelCount,
                               maximumSamplesPerBlock: configuration.maximumSamplesPerBlock)
        stream = try .init(sampleRate: configuration.sampleRate, windowSeconds: configuration.windowSeconds,
                           stepSeconds: configuration.stepSeconds, maximumBufferedSamples: configuration.maximumBufferedSamples)
    }
    /// Ordinary supported controls only. Atomic rejection of malformed input is
    /// our policy. No implicit tick on elapsed time or automatic backlog draining.
    mutating func detectorCall(selectedChannels: [[Double]], control: Control) throws -> Tick {
        guard (0...5).contains(control.trainingControl),
              selectedChannels.isEmpty || selectedChannels.count == configuration.selectedChannelCount else {
            throw Failure.invalidInput
        }
        var next = self
        let filtered: [[Double]]
        if selectedChannels.isEmpty { filtered = [] }
        else { filtered = try next.filter.apply(selectedChannels); try next.stream.append(filtered) }
        let epoch = next.stream.nextWithRemoval()
        let route: Route
        if epoch == nil { route = .waiting }
        else if control.classifierEmpty && !control.autoSamplingNeutral && control.trainingControl != 1 {
            route = .consumedWithoutFeatures
        } else { route = .extractFeatures }
        self = next
        return .init(route: route, filteredBlock: filtered, consumedEpoch: epoch)
    }
    /// Traced manager.stop resets the stream and requests training/background
    /// reset. It does NOT reset/reconstruct +0xb38 input-filter state. Returned
    /// effects are obligations for a downstream owner, not mocked side effects.
    mutating func stop() -> StopEffects {
        stream.reset()
        return .init(resetTrainingState: true, clearBackgroundMatrix: true, inputFilterReset: false)
    }
    /// Independent capture discontinuity policy, deliberately broader than stop.
    mutating func resetForGap() {
        filter.reset(); stream.reset()
    }
    /// Manager.init replaces the input filter and stream, then resets the stream.
    /// Caller supplies the actual propagated detection sample rate and recipe.
    mutating func initialize(configuration: Configuration) throws {
        self = try Self(configuration: configuration)
    }
}
