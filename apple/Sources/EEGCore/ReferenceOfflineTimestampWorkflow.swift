import Foundation

/// Type7 EEG-only offline branch, composed from the existing clock kernel.
/// Other packet types are rejected rather than silently treated as EEG.
/// Evidence: timing-motion-offline-20261011. No live acquisition integration.
struct ReferenceOfflineTimestampWorkflow {
    struct Output {
        let retainedInputIndices: [Int]
        let discardedInputIndices: [Int]
        let timestamps: [Double]
    }
    let configuration: ReferenceTimestampClock.Configuration
    let sampleRate: Double
    let startTime: Double
    let lastPreOffsetEEGTime: Double
    private(set) var clock: ReferenceTimestampClock?

    init(configuration: ReferenceTimestampClock.Configuration, sampleRate: Double,
         startTime: Double, lastPreOffsetEEGTime: Double) throws {
        guard sampleRate.isFinite, sampleRate > 0, startTime.isFinite, startTime > 0,
              lastPreOffsetEEGTime.isFinite else { throw ReferenceTimestampClock.Failure.invalidInput }
        // Validate configuration even before the first packet arrives.
        _ = try ReferenceTimestampClock(configuration: configuration, previousCounter: 0,
            eegTimestamp: startTime, motionTimestamp: startTime, cumulativeCounterDistance: 0)
        self.configuration = configuration; self.sampleRate = sampleRate
        self.startTime = startTime; self.lastPreOffsetEEGTime = lastPreOffsetEEGTime
    }

    mutating func process(_ packets: [ReferenceTimestampClock.Packet], maximumPackets: Int) throws -> Output {
        guard maximumPackets >= 0, packets.count <= maximumPackets,
              packets.allSatisfy({ $0.type == 16 && $0.interpolationFlag >= 0 &&
                  (0...configuration.maximumCounter).contains($0.counter) }) else {
            throw ReferenceTimestampClock.Failure.invalidInput
        }
        var next = clock
        var retained: [Int] = [], times: [Double] = []
        var start = 0
        if next == nil {
            guard let first = packets.first else { throw ReferenceTimestampClock.Failure.noEEGAnchor }
            // Offline scans forward, calls addFirstTimestamp on a singleton,
            // removes that prefix and prepends the successful anchor to output.
            let anchor = try ReferenceTimestampClock.anchor(packets: [first], suppliedTime: startTime,
                lastDataTimestamp: lastPreOffsetEEGTime, motionTimestamp: startTime,
                configuration: configuration, maximumPackets: 1)
            next = anchor.clock; retained.append(0); times.append(anchor.timestamp); start = 1
        }
        guard var working = next else { throw ReferenceTimestampClock.Failure.noEEGAnchor }
        for index in start..<packets.count {
            let sample = try working.process(packets[index], sampleRate: sampleRate)
            retained.append(index); times.append(sample.timestamp)
        }
        // Subsequent offline calls force nominal rate. No live clock sync or
        // hardware offset is called by processOfflineData. Atomic failure is ours.
        clock = working
        return Output(retainedInputIndices: retained, discardedInputIndices: [], timestamps: times)
    }
}

/// Ordinary (including mode7) motion timestamp branch only. Modes6/9/10
/// have different bodies and must not be routed through this helper.
struct ReferenceOrdinaryMotionClock {
    private(set) var previousCounter: Int?
    private(set) var unroundedTime: Double?
    let maximumCounter: Int
    let decimalPrecision: Int

    init(maximumCounter: Int, decimalPrecision: Int) throws {
        guard (1...65535).contains(maximumCounter), (0...9).contains(decimalPrecision) else {
            throw ReferenceTimestampClock.Failure.invalidConfiguration
        }
        self.maximumCounter = maximumCounter; self.decimalPrecision = decimalPrecision
    }

    mutating func process(counter: Int, sampleRate: Double, firstAnchorTime: Double) throws -> Double {
        guard (0...maximumCounter).contains(counter), sampleRate.isFinite, sampleRate > 0 else {
            throw ReferenceTimestampClock.Failure.invalidInput
        }
        let time: Double
        if let previousCounter, let unroundedTime {
            let modulus = maximumCounter + 1
            let distance = ((counter - previousCounter) % modulus + modulus) % modulus
            time = unroundedTime.addingProduct(1 / sampleRate, Double(distance))
        } else {
            // Caller supplies offlineStart if positive, otherwise actual
            // TimeUtils epoch-steady observation. This helper does not invent it.
            time = firstAnchorTime
        }
        guard time.isFinite, time >= 0 else { throw ReferenceTimestampClock.Failure.invalidInput }
        let rounded = try ReferenceTimestampClock.round(time, decimalPrecision: decimalPrecision)
        previousCounter = counter; unroundedTime = time
        return rounded
    }
}

/// removeBadCounterSample's observed behavior: check first out-of-time EEG,
/// report error22 and request reanchoring. Its history loop formats diagnostics;
/// it does not repair timestamps or delete samples despite the function name.
enum ReferenceTimestampResetGate {
    struct Decision: Equatable {
        let firstInvalidIndex: Int?
        var requiresReanchor: Bool { firstInvalidIndex != nil }
        var referenceErrorCode: Int { requiresReanchor ? 22 : 0 }
    }
    static func evaluate(_ packets: [ReferenceTimestampClock.TimedPacket], currentTime: Double,
                         maximumDeviation: Double, maximumPackets: Int) throws -> Decision {
        guard currentTime.isFinite, maximumDeviation.isFinite, maximumDeviation >= 0,
              maximumPackets >= 0, packets.count <= maximumPackets,
              packets.allSatisfy({ $0.timestamp.isFinite }) else {
            throw ReferenceTimestampClock.Failure.invalidInput
        }
        return Decision(firstInvalidIndex: packets.firstIndex {
            $0.type == 16 && abs(currentTime - $0.timestamp) > maximumDeviation
        })
    }
}
