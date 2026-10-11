import Foundation

/// Opt-in comparison bridge. Decoded measurements remain caller supplied; only
/// successful timestamp rows enter the shared resolved mental workflow. No clocks,
/// contact metadata, events or application actions are fabricated.
struct ReferenceTimedMentalWorkflow {
    enum Failure: Error { case incompatibleSampleRate, invalidMeasurements }
    struct Packet {
        let clock: ReferenceTimestampClock.Packet
        /// One decoded sample in the explicitly configured full montage order.
        let measurements: [Double]
    }
    struct Frame {
        let originals: [Packet]
        let timing: ReferenceLiveTimestampWorkflow.Output
        let mental: ReferenceResolvedMentalWorkflow.Frame?
        let discontinuityDetected: Bool
    }
    private(set) var timing: ReferenceLiveTimestampWorkflow
    private var mental: ReferenceResolvedMentalWorkflow
    private var lastAdmittedCounter: Int?
    var bufferedSamples: Int { mental.bufferedSamples }

    init(configuration: ReferenceLiveTimestampWorkflow.Configuration,
         mental: ReferenceResolvedMentalWorkflow) throws {
        guard Int(configuration.sampleRate) == mental.rawRecipe.sampleRate else {
            throw Failure.incompatibleSampleRate
        }
        timing = try .init(configuration: configuration); self.mental = mental
    }

    /// A failed/renewed timestamp anchor is an independent processing boundary:
    /// reset filter, window, background and scoring state together. This is our
    /// fail-closed policy, not a claim that Cortex resets all these downstream states.
    /// Exceptions are atomic for BOTH composed workflows. Empty batches do not
    /// silently drain a mental backlog or reset it.
    mutating func process(_ packets: [Packet], observedTime: Double,
                          overallContactQuality: Double,
                          managerControl: ReferenceManagerCadence.Control? = nil) throws -> Frame {
        guard packets.count <= timing.configuration.maximumPackets,
              overallContactQuality.isFinite,
              packets.allSatisfy({ $0.measurements.count == mental.inputChannels.count &&
                  $0.measurements.allSatisfy(\.isFinite) }) else { throw Failure.invalidMeasurements }
        var next = self
        let stamp = try next.timing.process(packets.map(\.clock), observedTime: observedTime)
        let result: ReferenceResolvedMentalWorkflow.Frame?
        var discontinuity = false
        switch stamp.status {
        case .warmingUp, .anchorRejected, .timestampRejected:
            next.mental.resetForGap(); next.lastAdmittedCounter = nil; result = nil
        case .empty:
            result = nil
        case .ready:
            if stamp.didReanchor { next.mental.resetForGap(); next.lastAdmittedCounter = nil }
            // Independent admission policy: the feature stream assumes uniform
            // samples, so neither missing nor duplicate counters may bridge it.
            // Caller-supplied interpolated rows qualify only when contiguous.
            let modulus = next.timing.configuration.clock.maximumCounter + 1
            var previous = next.lastAdmittedCounter
            for index in stamp.retainedInputIndices {
                let counter = packets[index].clock.counter
                if let previous, counter != (previous + 1) % modulus { discontinuity = true }
                previous = counter
            }
            // A rejected batch establishes the next counter baseline without
            // admitting its measurements. The next contiguous batch can recover.
            next.lastAdmittedCounter = previous
            if discontinuity {
                next.mental.resetForGap(); result = nil
            } else {
                let matrix = next.mental.inputChannels.indices.map { channel in
                    stamp.retainedInputIndices.map { packets[$0].measurements[channel] }
                }
                result = try next.mental.process(inputSamples: matrix,
                    overallContactQuality: overallContactQuality, managerControl: managerControl)
            }
        }
        self = next
        return .init(originals: packets, timing: stamp, mental: result, discontinuityDetected: discontinuity)
    }
}
