import Foundation

/// Body-backed mode7 EEG-only live timestamp orchestration. Input time must be
/// an explicit positive epoch-steady observation; this does not read a host clock.
/// Motion packages and other modes remain unsupported, not silently discarded.
struct ReferenceLiveTimestampWorkflow {
    typealias Clock = ReferenceTimestampClock
    struct Configuration {
        let clock: Clock.Configuration
        let sampleRate: UInt32
        let warmupSeconds: Double
        let maximumDeviation: Double
        let adaptiveTransitionSeconds: Double
        let hardwareOffset: Double
        let maximumPackets: Int
    }
    enum Status: Equatable { case empty, warmingUp, anchorRejected, timestampRejected, ready }
    struct Output {
        let status: Status
        let referenceErrorCode: Int
        let didReanchor: Bool
        let retainedInputIndices: [Int]
        let beforeHardwareOffset: [Double]
        let timestamps: [Double]
    }
    let configuration: Configuration
    private(set) var clock: Clock
    private(set) var ready = false
    private(set) var pendingOrigin = true
    private(set) var pendingAnchor = true
    private(set) var origin: Double = -1
    private(set) var lastPreOffsetEEGTime: Double = 1
    private(set) var adaptiveRate: Double

    init(configuration: Configuration) throws {
        guard configuration.sampleRate > 0, configuration.warmupSeconds.isFinite,
              configuration.warmupSeconds >= 0, configuration.maximumDeviation.isFinite,
              configuration.maximumDeviation >= 0, configuration.adaptiveTransitionSeconds.isFinite,
              configuration.adaptiveTransitionSeconds >= 0, configuration.hardwareOffset.isFinite,
              configuration.maximumPackets > 0 else { throw Clock.Failure.invalidConfiguration }
        self.configuration = configuration; adaptiveRate = Double(configuration.sampleRate)
        clock = try Clock(configuration: configuration.clock, previousCounter: 0,
            eegTimestamp: 1, motionTimestamp: 1, cumulativeCounterDistance: 0)
    }
    private mutating func requestReset() { ready = false; pendingOrigin = true; pendingAnchor = true }

    mutating func process(_ packets: [Clock.Packet], observedTime: Double) throws -> Output {
        guard packets.count <= configuration.maximumPackets,
              observedTime.isFinite, observedTime > 0,
              packets.allSatisfy({ $0.type == 16 && $0.interpolationFlag >= 0 &&
                  (0...configuration.clock.maximumCounter).contains($0.counter) }) else {
            throw Clock.Failure.invalidInput
        }
        // Independent transactional policy for unsupported/numerical exceptions.
        // Vendor error21/22 are outcomes with retained reset state, not exceptions.
        var next = self
        let result = try next.advance(packets, observedTime: observedTime)
        self = next
        return result
    }
    private mutating func advance(_ packets: [Clock.Packet], observedTime: Double) throws -> Output {
        var didReanchor = false
        func output(_ status: Status, _ code: Int, _ indices: [Int] = [],
                    _ before: [Double] = [], _ after: [Double] = []) -> Output {
            .init(status: status, referenceErrorCode: code, didReanchor: didReanchor, retainedInputIndices: indices,
                  beforeHardwareOffset: before, timestamps: after)
        }
        guard !packets.isEmpty else { return output(.empty, 0) }
        if abs(observedTime - clock.eegTimestamp) > configuration.maximumDeviation { requestReset() }
        if pendingOrigin { pendingOrigin = false; origin = observedTime }
        if !ready {
            if observedTime - origin < configuration.warmupSeconds {
                try clock.setWarmupTime(observedTime)
                return output(.warmingUp, 21)
            }
            ready = true
        }
        var indices = Array(packets.indices)
        if pendingAnchor {
            guard lastPreOffsetEEGTime < observedTime else {
                requestReset(); return output(.anchorRejected, 21)
            }
            // Live addFirstTimestamp retains LAST EEG, unlike offline's first.
            let last = packets.count - 1
            try clock.reanchor(counter: packets[last].counter, time: observedTime)
            origin = observedTime; pendingAnchor = false; indices = [last]; didReanchor = true
        }
        let elapsed = observedTime - origin
        guard elapsed.isFinite, elapsed >= 0 else { throw Clock.Failure.invalidInput }
        let nominal = Double(configuration.sampleRate)
        let rate = elapsed <= configuration.adaptiveTransitionSeconds ? nominal : adaptiveRate
        var timed: [Clock.TimedPacket] = []
        for index in indices {
            let sample = try clock.process(packets[index], sampleRate: rate)
            timed.append(.init(type: 16, timestamp: sample.timestamp))
        }
        // Updated AFTER processing; existing adaptive rate serves current batch.
        let decision = try Clock.rateDecision(elapsedSinceAnchor: elapsed,
            transitionSeconds: configuration.adaptiveTransitionSeconds, forceNominalRates: false,
            nominal: .init(eeg: nominal, motion: 0), adaptive: .init(eeg: adaptiveRate, motion: 0),
            cumulativeCounterDistance: clock.cumulativeCounterDistance,
            configuredEEGRate: configuration.sampleRate, configuredMotionRate: 0, headsetMode: 7)
        if let rates = decision.adaptiveRatesForNextBatch { adaptiveRate = rates.eeg }
        _ = try clock.synchronize(realTime: observedTime, headsetMode: 7, configuredMotionRate: 0)
        let gate = try ReferenceTimestampResetGate.evaluate(timed, currentTime: observedTime,
            maximumDeviation: configuration.maximumDeviation, maximumPackets: configuration.maximumPackets)
        if gate.requiresReanchor {
            requestReset()
            return output(.timestampRejected, 22, indices, timed.map(\.timestamp))
        }
        let corrected = try Clock.hardwareTiming(packets: timed, offset: configuration.hardwareOffset,
            maximumPackets: configuration.maximumPackets)
        if let last = corrected.lastEEGBeforeCorrection { lastPreOffsetEEGTime = last }
        return output(.ready, 0, indices, timed.map(\.timestamp), corrected.afterCorrection.map(\.timestamp))
    }
}
