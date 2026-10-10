import Foundation

/// Comparison-only remembered-slot and batch-output orchestration.
/// Input is already extracted data. It does not decode, acquire or qualify hardware.
struct ReferenceContactQualityRouting {
    enum Failure: Error { case invalidInput, unsupportedSize }
    struct Packet {
        let packetType: Int
        let counter: Int32
        let rawCQ: Double?
        let timestamp: Double
    }
    struct Batch {
        let changedOrdinals: [Int]
        let diagnostics: ReferenceContactQualityMapping.Diagnostics
        // makeCQ emits the batch-final state map and overall for every provided row.
        let timestamps: [Double]
        let stateRows: [[Int]]
        let overallRows: [Double]
    }
    let recipe: ReferenceTypeSevenCQRecipe.Recipe
    let maximumPackets: Int
    private(set) var originalRaw: [Double]
    private(set) var rememberedMapped: [Double]

    init(recipe: ReferenceTypeSevenCQRecipe.Recipe, maximumPackets: Int) throws {
        guard maximumPackets > 0 else { throw Failure.unsupportedSize }
        guard recipe.mode == 7, recipe.eegSampleRate == 128, recipe.eegResolution == 16,
              recipe.channels.count == 14, recipe.initialRememberedRawValues.count == 14,
              recipe.initialRememberedRawValues.allSatisfy({ $0.isFinite }),
              recipe.channels.allSatisfy({ channel in
                  let config = channel.configuration
                  return config.divisor > 0 && config.thresholds.count == 4 &&
                    config.thresholds.allSatisfy({ $0.isFinite }) &&
                    zip(config.thresholds, config.thresholds.dropFirst()).allSatisfy({ $0.0 < $0.1 })
              }) else { throw Failure.invalidInput }
        self.recipe = recipe
        self.maximumPackets = maximumPackets
        originalRaw = recipe.initialRememberedRawValues
        rememberedMapped = recipe.initialRememberedRawValues
    }

    /// Exact numeric predicate at 0x101068dd0..df8. 128 is a constructor constant;
    /// this is not a duplicate-counter detector. Modes1/3 are predicate fixtures only.
    static func passesPacketGate(packetType: Int, counter: Int32, mode: Int) -> Bool {
        packetType == 16 && !(counter == 128 && (mode | 2) == 3)
    }

    /// Actual type7/rate128/count14 branch of calculateCqChannelId.
    /// Nonnegative counters are our support policy; unsupported signed tuples rejected.
    static func ordinal(counter: Int32) throws -> Int? {
        guard counter >= 0 else { throw Failure.invalidInput }
        let result = Int(counter % 64)
        return result < 14 ? result : nil
    }

    mutating func process(_ packets: [Packet]) throws -> Batch {
        guard packets.count <= maximumPackets else { throw Failure.unsupportedSize }
        guard packets.allSatisfy({ $0.timestamp.isFinite && $0.counter >= 0 }) else { throw Failure.invalidInput }
        // Prevalidate used observations; atomic failure is our bounded adapter policy.
        for packet in packets where Self.passesPacketGate(packetType: packet.packetType,
                                                         counter: packet.counter, mode: recipe.mode) {
            if try Self.ordinal(counter: packet.counter) != nil {
                guard let raw = packet.rawCQ, raw.isFinite else { throw Failure.invalidInput }
            }
        }
        var changed: [Int] = []
        for packet in packets where Self.passesPacketGate(packetType: packet.packetType,
                                                         counter: packet.counter, mode: recipe.mode) {
            guard let slot = try Self.ordinal(counter: packet.counter), let raw = packet.rawCQ else { continue }
            originalRaw[slot] = raw
            rememberedMapped[slot] = try ReferenceContactQualityMapping.mappedValue(raw,
                eeg16Bit: ReferenceContactQualityMapping.typeSevenUses16Bit(mode: recipe.mode), headsetType: 7)
            changed.append(slot)
        }
        let channels = try recipe.channels.indices.map { slot in
            let config = recipe.channels[slot].configuration
            let mapped = rememberedMapped[slot]
            return ReferenceContactQualityMapping.ChannelDiagnostic(raw: originalRaw[slot], mapped: mapped,
                normalized: (mapped - Double(config.offset)) / Double(config.divisor),
                state: try ReferenceContactQualityMapping.state(mappedValue: mapped, offset: config.offset,
                    divisor: config.divisor, thresholds: config.thresholds, f68RangeGroup: config.f68RangeGroup))
        }
        let states = channels.map { $0.state }
        let diagnostics = ReferenceContactQualityMapping.Diagnostics(channels: channels,
            overall: try ReferenceContactQualityMapping.overall(states: states, maximumChannels: 14))
        return Batch(changedOrdinals: changed, diagnostics: diagnostics,
            timestamps: packets.map { $0.timestamp }, stateRows: Array(repeating: states, count: packets.count),
            overallRows: Array(repeating: diagnostics.overall, count: packets.count))
    }

    struct Detection {
        let lastStates: [Int: Int]
        let epochMinimumStates: [Int: Int]
        let minimum: Int
        let overall: Double
        let timestamp: Double
    }

    /// DetectionCoreCQ::set explicit numeric-channel matrix contract. Ordinary values
    /// truncate toward zero before class validation. Special IDs146/147/152/163 excluded;
    /// overall147 and timestamp152 take the final row. No implicit channel-ID schema.
    static func detection(rows: [[Double]], channelIDs: [Int], maximumRows: Int) throws -> Detection {
        guard maximumRows > 0, rows.count <= maximumRows, channelIDs.count <= 32 else { throw Failure.unsupportedSize }
        guard Set(channelIDs).count == channelIDs.count,
              rows.allSatisfy({ $0.count == channelIDs.count && $0.allSatisfy({ $0.isFinite }) }) else {
            throw Failure.invalidInput
        }
        guard !rows.isEmpty && !channelIDs.isEmpty else {
            return Detection(lastStates: [:], epochMinimumStates: [:], minimum: 0, overall: 0, timestamp: 0)
        }
        var minima = Dictionary(uniqueKeysWithValues: channelIDs.map { ($0, 4) })
        var last: [Int: Int] = [:]
        var minimum = 4
        var overall = 0.0
        var timestamp = 0.0
        let special = Set([146, 147, 152, 163])
        for (rowIndex, row) in rows.enumerated() {
            for (column, channelID) in channelIDs.enumerated() {
                let value = row[column]
                if rowIndex == rows.count - 1 {
                    if channelID == 147 { overall = value }
                    if channelID == 152 { timestamp = value }
                }
                if special.contains(channelID) { continue }
                guard value > -1 && value < 5 else { throw Failure.invalidInput }
                let state = Int(value)
                if rowIndex == rows.count - 1 { last[channelID] = state }
                minima[channelID] = min(minima[channelID] ?? 0, state)
                minimum = min(minimum, state)
            }
        }
        return Detection(lastStates: last, epochMinimumStates: minima, minimum: minimum,
                         overall: overall, timestamp: timestamp)
    }
}
