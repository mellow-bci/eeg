import Foundation

/// Comparison-only numerical CQ mapping. Caller must supply resolved hardware/configuration
/// branches; this does not turn a decoded raw CQ word into a hardware-qualified indicator.
enum ReferenceContactQualityMapping {
    enum Failure: Error { case invalidInput, unsupportedSize }

    /// updateCQValues 0x101068ef0..8f4c scales eligible 16-bit, non-type-5 values.
    static func mappedValue(_ value: Double, eeg16Bit: Bool, headsetType: Int) throws -> Double {
        guard value.isFinite else { throw Failure.invalidInput }
        return eeg16Bit && headsetType != 5 ? value * 0.25 : value
    }

    /// updateCQStates 0x1010691cc..9244. Parameters are explicit, not guessed defaults.
    static func state(mappedValue: Double, offset: Int32, divisor: Int32,
                      thresholds: [Double], f68RangeGroup: Bool) throws -> Int {
        guard mappedValue.isFinite, divisor > 0, thresholds.count == 4,
              thresholds.allSatisfy({ $0.isFinite }),
              zip(thresholds, thresholds.dropFirst()).allSatisfy({ $0.0 < $0.1 }) else {
            throw Failure.invalidInput
        }
        let normalized = (mappedValue - Double(offset)) / Double(divisor)
        guard normalized.isFinite else { throw Failure.invalidInput }
        if normalized < thresholds[0] { return 0 }
        if normalized < thresholds[1] { return 1 }
        if normalized < thresholds[2] { return 2 }
        if normalized < thresholds[3] { return f68RangeGroup ? 3 : 2 }
        return 4
    }

    /// Core calculateCQOverall 0x101f25c38: lowest min(3,n) states / (4*k) * 100.
    /// Explicit allocation bound is our support policy; states are supplied, not inferred.
    static func overall(states: [Int], maximumChannels: Int) throws -> Double {
        guard maximumChannels > 0, states.count <= maximumChannels else { throw Failure.unsupportedSize }
        guard states.allSatisfy({ (0...4).contains($0) }) else { throw Failure.invalidInput }
        guard !states.isEmpty else { return 0 }
        let worst = states.sorted().prefix(3)
        return Double(worst.reduce(0, +)) / (Double(worst.count) * 4) * 100
    }
    struct ChannelConfiguration {
        let offset: Int32
        let divisor: Int32
        let thresholds: [Double]
        let f68RangeGroup: Bool
    }
    struct ChannelDiagnostic {
        let raw: Double
        let mapped: Double
        let normalized: Double
        let state: Int
    }
    struct Diagnostics {
        let channels: [ChannelDiagnostic]
        let overall: Double
    }

    /// Static type-7 branch only (isEeg16Bit jump table index6 -> mode4/7).
    /// Caller must have established type7; this is not firmware/hardware qualification.
    static func typeSevenUses16Bit(mode: Int) -> Bool { mode == 4 || mode == 7 }

    /// Stateless snapshot composition. Raw and intermediate measurements remain distinct.
    /// Snapshot timing and persistent-slot update ownership stay with the hardware adapter.
    static func snapshot(rawValues: [Double], configurations: [ChannelConfiguration],
                         eeg16Bit: Bool, headsetType: Int, maximumChannels: Int) throws -> Diagnostics {
        guard rawValues.count == configurations.count else { throw Failure.invalidInput }
        guard maximumChannels > 0, rawValues.count <= maximumChannels else { throw Failure.unsupportedSize }
        let channels = try zip(rawValues, configurations).map { raw, configuration in
            let mapped = try mappedValue(raw, eeg16Bit: eeg16Bit, headsetType: headsetType)
            let result = try state(mappedValue: mapped, offset: configuration.offset,
                                   divisor: configuration.divisor, thresholds: configuration.thresholds,
                                   f68RangeGroup: configuration.f68RangeGroup)
            return ChannelDiagnostic(raw: raw, mapped: mapped,
                                     normalized: (mapped - Double(configuration.offset)) / Double(configuration.divisor),
                                     state: result)
        }
        return Diagnostics(channels: channels,
                           overall: try overall(states: channels.map { $0.state }, maximumChannels: maximumChannels))
    }

}
