import Foundation

/// Reconstructed configuration selection, not a vendor settings-file parser.
/// Values are explicitly supplied; no participant profile or vendor table is bundled.
/// Evidence: sensitivity-continuation-20261011. Finite values are our support policy.
enum ReferenceSensitivityConfiguration {
    enum InputError: Error, Equatable { case nonFiniteValue, invalidActionThresholds }
    struct Entry: Sendable, Equatable {
        let version: String
        let values: [Double]
    }
    struct JSONEntry: Sendable {
        let headsetType: Int32
        let version: String
        /// Already-converted JSON numbers. Nil models concreteDouble's default 0.
        let values: [Double?]
    }

    /// Core::normalize at 0x101fc96c8, table 0x102fd6e68.
    static func normalizedHeadsetType(_ type: Int32) -> Int32 {
        switch type {
        case 2: return 1
        case 3, 4, 7, 8: return 4
        case 6: return 5
        default: return type
        }
    }

    /// Fresh-map boundary: caller supplies Config::mcSensitivity's parsed output.
    /// A nonempty INI map wins as a whole, even if the requested headset is absent.
    /// Sorted keys preserve QMap iteration order when normalization aliases collide.
    /// JSON entries must be in the reference's object-key iteration order.
    static func resolve(parsedINI: [Int32: [Double]], orderedJSON: [JSONEntry]) throws -> [Int32: Entry] {
        var result: [Int32: Entry] = [:]
        if !parsedINI.isEmpty {
            for type in parsedINI.keys.sorted() {
                let values = parsedINI[type]!
                guard values.allSatisfy(\.isFinite) else { throw InputError.nonFiniteValue }
                result[normalizedHeadsetType(type)] = Entry(version: "configIniFile", values: values)
            }
        } else {
            for entry in orderedJSON where !entry.version.isEmpty {
                let values = entry.values.map { $0 ?? 0 }
                guard values.allSatisfy(\.isFinite) else { throw InputError.nonFiniteValue }
                result[normalizedHeadsetType(entry.headsetType)] = Entry(version: entry.version, values: values)
            }
        }
        return result
    }

    static func managerMap(_ entries: [Int32: Entry]) -> [Int32: [Double]] {
        entries.mapValues(\.values)
    }

    static func version(headsetType: Int32, entries: [Int32: Entry]) -> String {
        entries[normalizedHeadsetType(headsetType)]?.version ?? "notFound"
    }

    /// API::mentalCommandActionSensitivity set: four values, each integer 1...10.
    /// Qt QVariant conversion happens before this boundary and is not imitated.
    static func validateActionThresholds(_ values: [Int32]) throws -> [Int32] {
        guard values.count == 4, values.allSatisfy({ (1...10).contains($0) }) else {
            throw InputError.invalidActionThresholds
        }
        return values
    }

    struct ManagerState: Sendable {
        private(set) var map: [Int32: [Double]] = [:]
        private(set) var selectedValues: [Double] = []

        /// Empty input is ignored. Nonempty input replaces the map, but does not
        /// refresh the selected list (setMcSensitivity 0x100b39bb4).
        mutating func set(_ replacement: [Int32: [Double]]) throws {
            guard !replacement.isEmpty else { return }
            guard replacement.values.allSatisfy({ $0.allSatisfy(\.isFinite) }) else {
                throw InputError.nonFiniteValue
            }
            map = replacement
        }

        /// Clear first; missing key stays empty and therefore uses the scoring
        /// fallback already implemented by ReferenceTrainingBank.classWeights.
        mutating func select(headsetType: Int32) {
            selectedValues = []
            selectedValues = map[normalizedHeadsetType(headsetType)] ?? []
        }

        func classWeights(activeActionCount: Int, thresholdSlots: [Int32]) throws -> [Double] {
            try ReferenceTrainingBank.classWeights(activeActionCount: activeActionCount,
                thresholdSlots: thresholdSlots, configuredWeightTable: selectedValues)
        }
    }
}
