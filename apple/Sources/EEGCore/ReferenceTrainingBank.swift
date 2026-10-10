import Foundation

/// Static-body comparison helpers. Not connected to acquisition or live commands.
enum ReferenceTrainingBank {
    struct ClassEntry: Equatable, Codable {
        var classReferenceID: Int32
        var distributions: [ReferenceGaussianPooling.Distribution]
    }
    enum InputError: Error, Equatable {
        case invalidCapacity, capacityExceeded, invalidTimestamp, invalidThresholds
        case invalidWeightTable, invalidActionCount, nonFiniteWeight
    }

    /// Feature rows / epoch columns are already accepted by the caller.
    /// Empty data or timestamp input returns the bank unchanged, as in addUpdate.
    /// Only the first timestamp is consumed; fractional seconds truncate toward zero.
    static func addUpdate(featureRows: [[Double]], updateTimes: [Double],
                          classReferenceID: Int32, bank: [ClassEntry],
                          maximumEpochs: Int, maximumClasses: Int,
                          maximumDistributionsPerClass: Int) throws -> [ClassEntry] {
        if featureRows.isEmpty || featureRows.allSatisfy({ $0.isEmpty }) || updateTimes.isEmpty { return bank }
        guard maximumClasses > 0, maximumDistributionsPerClass > 0 else { throw InputError.invalidCapacity }
        guard bank.count <= maximumClasses,
              bank.allSatisfy({ $0.distributions.count <= maximumDistributionsPerClass }) else {
            throw InputError.capacityExceeded
        }
        let index = bank.firstIndex { $0.classReferenceID == classReferenceID }
        if let index {
            guard bank[index].distributions.count < maximumDistributionsPerClass else { throw InputError.capacityExceeded }
        } else {
            guard bank.count < maximumClasses else { throw InputError.capacityExceeded }
        }
        let timestamp = updateTimes[0]
        // Independent bounded domain: exclude ARM out-of-range FCVTZU behavior.
        guard timestamp.isFinite, timestamp >= 0, timestamp <= Double(UInt32.max) else {
            throw InputError.invalidTimestamp
        }
        let statistics = try ReferenceTrainingStatistics.fit(featureRows: featureRows,
            coordinates: Array(featureRows.indices), maximumEpochs: maximumEpochs)
        let distribution = ReferenceGaussianPooling.Distribution(counts: statistics.epochCounts,
            mean: statistics.average, covariance: statistics.covariance,
            updateTime: UInt32(timestamp.rounded(.towardZero)))
        var result = bank
        if let index { result[index].distributions.append(distribution) }
        else { result.append(ClassEntry(classReferenceID: classReferenceID, distributions: [distribution])) }
        return result
    }

    /// Returned weights are unnormalized. Position zero is neutral, then action slots.
    /// Exactly ten supplied entries select the reference's lookup branch; any other
    /// table length selects its exp10 branch. Table values are never fabricated.
    /// Four threshold slots are required even if fewer active actions are requested.
    static func classWeights(activeActionCount: Int, thresholdSlots: [Int32],
                             configuredWeightTable: [Double]) throws -> [Double] {
        guard (1...4).contains(activeActionCount) else { throw InputError.invalidActionCount }
        guard thresholdSlots.count == 4 else { throw InputError.invalidThresholds }
        let tableMode = configuredWeightTable.count == 10
        if tableMode {
            guard configuredWeightTable.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw InputError.invalidWeightTable }
        }
        var weights = [1.0]
        for threshold in thresholdSlots.prefix(activeActionCount) {
            let value: Double
            if tableMode {
                // No signed overflow at Int32.min: widen before threshold - 1.
                let index = min(9, max(0, Int64(threshold) - 1))
                value = configuredWeightTable[Int(index)]
            } else {
                value = pow(10, (Double(threshold) - 5) * 0.5)
            }
            guard value.isFinite else { throw InputError.nonFiniteWeight }
            weights.append(value)
        }
        return weights
    }
}
