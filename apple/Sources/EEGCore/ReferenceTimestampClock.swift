import Foundation

/// Comparison-only EEG timestamp arithmetic/state. No acquisition integration.
/// Explicit anchor/rate/precision: full DataTimeStamp orchestration is not implied.
/// Evidence: timestamp-clock-continuation-20261011.
struct ReferenceTimestampClock {
    enum Failure: Error { case invalidConfiguration, invalidInput, nonfiniteOutput, resetRequired, noEEGAnchor, resourceLimit }
    struct Configuration {
        let maximumCounter: Int
        let decimalPrecision: Int
        let historyCapacity: Int
    }
    struct Packet: Equatable {
        let type: Int
        let counter: Int
        /// ExtractedPackage+8; zero inserts into timestamp history.
        let interpolationFlag: Int
    }
    struct HistoryEntry: Equatable { let counter: Int; let timestamp: Double }
    struct Sample: Equatable {
        let timestamp: Double
        let unroundedTimestamp: Double
        let counterDistance: Int
        let insertedIntoHistory: Bool
    }
    struct Synchronization: Equatable {
        let correction: Double
        let motionTimestampWasNegative: Bool
        let motionTimestampReset: Bool
    }
    let configuration: Configuration
    private(set) var previousCounter: Int
    private(set) var eegTimestamp: Double
    private(set) var motionTimestamp: Double
    private(set) var cumulativeCounterDistance: UInt32
    private(set) var history: [HistoryEntry] = []
    private(set) var consecutivePositiveCorrections: UInt32 = 0
    private(set) var consecutiveNegativeCorrections: UInt32 = 0

    /// Caller supplies an already qualified anchor. Startup constructor defaults
    /// and external TimeUtils conversion are intentionally not invented.
    init(configuration: Configuration, previousCounter: Int, eegTimestamp: Double,
         motionTimestamp: Double, cumulativeCounterDistance: UInt32) throws {
        guard (1...65535).contains(configuration.maximumCounter),
              (0...9).contains(configuration.decimalPrecision),
              (1...1_000_000).contains(configuration.historyCapacity) else { throw Failure.invalidConfiguration }
        guard (0...configuration.maximumCounter).contains(previousCounter),
              eegTimestamp.isFinite, eegTimestamp >= 0, motionTimestamp.isFinite else { throw Failure.invalidInput }
        self.configuration = configuration
        self.previousCounter = previousCounter
        self.eegTimestamp = eegTimestamp
        self.motionTimestamp = motionTimestamp
        self.cumulativeCounterDistance = cumulativeCounterDistance
    }

    /// Supported successful addFirstTimestamp branch: last type16 packet retained.
    /// Returns its original index and rounded anchor, so discarded packets remain
    /// observable to the caller. Reset/no-EEG paths fail explicitly (our policy).
    static func anchor(packets: [Packet], suppliedTime: Double, lastDataTimestamp: Double,
                       motionTimestamp: Double, configuration: Configuration,
                       maximumPackets: Int) throws -> (clock: Self, retainedIndex: Int, timestamp: Double) {
        guard maximumPackets >= 0, packets.count <= maximumPackets,
              suppliedTime.isFinite, suppliedTime >= 0, lastDataTimestamp.isFinite else { throw Failure.invalidInput }
        guard let index = packets.lastIndex(where: { $0.type == 16 }) else { throw Failure.noEEGAnchor }
        guard lastDataTimestamp < suppliedTime else { throw Failure.resetRequired }
        // Reverse scan decrements x22 by 0x3a0 before loading +0x39c.
        // Relative to selected packet base this is +0xc, the ordinary counter.
        let clock = try Self(configuration: configuration, previousCounter: packets[index].counter,
                             eegTimestamp: suppliedTime, motionTimestamp: motionTimestamp,
                             cumulativeCounterDistance: 1)
        return (clock, index, try round(suppliedTime, decimalPrecision: configuration.decimalPrecision))
    }

    /// processEeg scalar contract. Duplicate counters have distance0; this method
    /// does not silently drop them. Parent's removeBadCounterSample is separate.
    mutating func process(_ packet: Packet, sampleRate: Double) throws -> Sample {
        guard packet.type == 16, (0...configuration.maximumCounter).contains(packet.counter),
              packet.interpolationFlag >= 0, sampleRate.isFinite, sampleRate > 0 else { throw Failure.invalidInput }
        let modulus = configuration.maximumCounter + 1
        let distance = ((packet.counter - previousCounter) % modulus + modulus) % modulus
        let time = eegTimestamp.addingProduct(1 / sampleRate, Double(distance))
        guard time.isFinite, time >= 0 else { throw Failure.nonfiniteOutput }
        let rounded = try Self.round(time, decimalPrecision: configuration.decimalPrecision)
        let (total, overflow) = cumulativeCounterDistance.addingReportingOverflow(UInt32(distance))
        guard !overflow else { throw Failure.resourceLimit } // Our fail-closed overflow policy.
        var nextHistory = history
        let insert = packet.interpolationFlag == 0
        if insert {
            if nextHistory.count >= configuration.historyCapacity { nextHistory.removeFirst() }
            nextHistory.append(.init(counter: packet.counter, timestamp: rounded))
        }
        eegTimestamp = time; previousCounter = packet.counter
        cumulativeCounterDistance = total; history = nextHistory
        return .init(timestamp: rounded, unroundedTimestamp: time,
                     counterDistance: distance, insertedIntoHistory: insert)
    }

    /// Recovered synchronization step called explicitly; not a timer. Parent
    /// passes its self+0x1c0/+0x1c8 clock pair to this routine.
    mutating func synchronize(realTime: Double, headsetMode: Int, configuredMotionRate: Int) throws -> Synchronization {
        guard realTime.isFinite else { throw Failure.invalidInput }
        let difference = realTime - eegTimestamp
        guard difference.isFinite else { throw Failure.nonfiniteOutput }
        let negativeThreshold = Double(bitPattern: 0xbf0a36e2eb1c432d)
        let positiveThreshold = Double(bitPattern: 0x3f0a36e2eb1c432d)
        let correction: Double
        var positive: UInt32 = 0, negative: UInt32 = 0
        if difference + negativeThreshold > 0 {
            correction = Double(bitPattern: 0x3f1a36e2eb1c432d)
            let (value, overflow) = consecutivePositiveCorrections.addingReportingOverflow(1)
            guard !overflow else { throw Failure.resourceLimit }; positive = value
        } else if difference + positiveThreshold < 0 {
            correction = Double(bitPattern: 0xbf1a36e2eb1c432d)
            let (value, overflow) = consecutiveNegativeCorrections.addingReportingOverflow(1)
            guard !overflow else { throw Failure.resourceLimit }; negative = value
        } else { correction = 0 }
        let eeg = correction == 0 ? eegTimestamp : eegTimestamp + correction
        let motion = configuredMotionRate <= 0 ? 0 : (correction == 0 ? motionTimestamp : motionTimestamp + correction)
        guard eeg.isFinite, eeg >= 0, motion.isFinite else { throw Failure.nonfiniteOutput }
        let warn = (headsetMode == 4 || headsetMode == 7) && motionTimestamp < 0
        eegTimestamp = eeg; motionTimestamp = motion
        consecutivePositiveCorrections = positive; consecutiveNegativeCorrections = negative
        return .init(correction: correction, motionTimestampWasNegative: warn,
                     motionTimestampReset: configuredMotionRate <= 0)
    }

    /// Observed constructor constants; callers explicitly choose them.
    static let observedDecimalPrecision = 6
    static let observedHistoryCapacity = 5
    static let observedAdaptiveTransitionSeconds: Double = 60

    struct Rates: Equatable { let eeg: Double; let motion: Double }
    struct RateDecision: Equatable {
        let usedNominalRates: Bool
        let ratesForCurrentBatch: Rates
        /// Vendor updates adaptive state AFTER timestamping the batch.
        let adaptiveRatesForNextBatch: Rates?
    }
    static func rateDecision(elapsedSinceAnchor: Double, transitionSeconds: Double,
                             forceNominalRates: Bool, nominal: Rates, adaptive: Rates,
                             cumulativeCounterDistance: UInt32, configuredEEGRate: UInt32,
                             configuredMotionRate: UInt32, headsetMode: Int) throws -> RateDecision {
        guard elapsedSinceAnchor.isFinite, elapsedSinceAnchor >= 0,
              transitionSeconds.isFinite, transitionSeconds >= 0,
              nominal.eeg.isFinite, nominal.eeg > 0, nominal.motion.isFinite, nominal.motion >= 0,
              adaptive.eeg.isFinite, adaptive.eeg >= 0, adaptive.motion.isFinite, adaptive.motion >= 0 else {
            throw Failure.invalidInput
        }
        let useNominal = elapsedSinceAnchor <= transitionSeconds || forceNominalRates
        if useNominal {
            return .init(usedNominalRates: true, ratesForCurrentBatch: nominal, adaptiveRatesForNextBatch: nil)
        }
        guard elapsedSinceAnchor > 0, cumulativeCounterDistance > 0, configuredEEGRate > 0,
              adaptive.eeg > 0 else { throw Failure.invalidInput }
        let eeg = Double(cumulativeCounterDistance - 1) / elapsedSinceAnchor
        let motionFactor = headsetMode == 9 ? Double(bitPattern: 0x401999999999999a) : Double(configuredMotionRate)
        let motion = (eeg * motionFactor) / Double(configuredEEGRate)
        guard eeg.isFinite, eeg > 0, motion.isFinite else { throw Failure.nonfiniteOutput }
        return .init(usedNominalRates: false, ratesForCurrentBatch: adaptive,
                     adaptiveRatesForNextBatch: .init(eeg: eeg, motion: motion))
    }
    struct TimedPacket: Equatable { let type: Int; let timestamp: Double }
    struct HardwareTiming: Equatable {
        let beforeCorrection: [TimedPacket]
        let afterCorrection: [TimedPacket]
        /// State+0x200 is captured before subtraction, from last EEG packet.
        let lastEEGBeforeCorrection: Double?
        let subtractedOffset: Double
    }
    static func hardwareTiming(packets: [TimedPacket], offset: Double, maximumPackets: Int) throws -> HardwareTiming {
        guard maximumPackets >= 0, packets.count <= maximumPackets, offset.isFinite,
              packets.allSatisfy({ $0.timestamp.isFinite }) else { throw Failure.invalidInput }
        let corrected = packets.map { TimedPacket(type: $0.type, timestamp: $0.timestamp - offset) }
        guard corrected.allSatisfy({ $0.timestamp.isFinite }) else { throw Failure.nonfiniteOutput }
        return .init(beforeCorrection: packets, afterCorrection: corrected,
                     lastEEGBeforeCorrection: packets.last(where: { $0.type == 16 })?.timestamp,
                     subtractedOffset: offset)
    }

    static func round(_ value: Double, decimalPrecision: Int) throws -> Double {
        // Exactly the ten static table entries inspected, no extrapolated domain.
        let scales: [Double] = [1,10,100,1000,10000,100000,1000000,10000000,100000000,1000000000]
        guard (0..<scales.count).contains(decimalPrecision), value.isFinite else { throw Failure.invalidInput }
        let scaled = value * scales[decimalPrecision]
        guard scaled.isFinite else { throw Failure.nonfiniteOutput }
        return scaled.rounded(.toNearestOrAwayFromZero) / scales[decimalPrecision]
    }
}
