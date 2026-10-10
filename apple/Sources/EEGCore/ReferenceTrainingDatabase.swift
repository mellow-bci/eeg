import Foundation

/// Typed, in-memory reconstruction of the database wrapper's class orchestration.
/// No vendor profile serialization, encryption or storage backend is reproduced.
/// Evidence: training-persistence-continuation-20261011. Caller owns durability.
enum ReferenceTrainingDatabase {
    typealias ClassEntry = ReferenceTrainingBank.ClassEntry
    enum InputError: Error, Equatable {
        case invalidClassReference, invalidMatrix, columnMismatch, epochCountMismatch
        case invalidLimit, unsupportedPooling
    }
    enum SaveResult: Equatable { case ignoredInvalidCounts, saved }
    struct Store {
        var gaussian: [Int32: ClassEntry] = [:]
        /// Persisted orientation: epoch rows, feature/timestamp columns.
        var featureRows: [Int32: [[Double]]] = [:]
        var timestampRows: [Int32: [[Double]]] = [:]
    }
    struct FeatureData: Equatable {
        /// Returned orientation: feature/timestamp rows, epoch columns.
        let features: [[[Double]]]
        let timestamps: [[[Double]]]
    }

    static func loadGaussian(classIDs: [Int32], store: Store) throws -> [ClassEntry] {
        try classIDs.map { id in
            guard let entry = store.gaussian[id] else {
                return ClassEntry(classReferenceID: id, distributions: [])
            }
            guard entry.classReferenceID != -1 else { throw InputError.invalidClassReference }
            // Existing payload replaces the initialized ID; no equality repair.
            return entry
        }
    }

    /// Invalid vector counts are a logged no-op in Cortex; model that explicitly.
    /// Classes commit sequentially. A later error does not undo prior class writes.
    static func saveGaussian(classIDs: [Int32], entries: [ClassEntry], append: Bool,
                             maximumDistributions: Int, store: inout Store) throws -> SaveResult {
        guard !classIDs.isEmpty, classIDs.count == entries.count else { return .ignoredInvalidCounts }
        guard maximumDistributions >= 0 else { throw InputError.invalidLimit } // Our finite domain.
        for (id, incoming) in zip(classIDs, entries) {
            guard incoming.classReferenceID != -1 else { throw InputError.invalidClassReference }
            var value = incoming
            if append, let previous = store.gaussian[id] {
                value = ClassEntry(classReferenceID: previous.classReferenceID,
                                   distributions: previous.distributions + incoming.distributions)
            }
            if maximumDistributions > 0 {
                while value.distributions.count > maximumDistributions {
                    guard let combined = try ReferenceGaussianPooling.combine(value.distributions[0],
                        value.distributions[1], useFirstUpdateTime: false) else {
                        throw InputError.unsupportedPooling
                    }
                    // Vendor assigns combined into index1, then removes index0.
                    value.distributions[1] = combined
                    value.distributions.removeFirst()
                }
            }
            store.gaussian[id] = value
        }
        return .saved
    }

    static func loadFeatures(classIDs: [Int32], store: Store) throws -> FeatureData {
        FeatureData(features: try classIDs.map { try transpose(store.featureRows[$0] ?? []) },
                    timestamps: try classIDs.map { try transpose(store.timestampRows[$0] ?? []) })
    }

    /// Existing rows precede new rows. Empty feature OR timestamp matrix skips slot.
    /// Feature then timestamp writes precede the accumulated epoch-count assertion;
    /// therefore a count failure leaves both writes present, without invented rollback.
    static func saveFeatures(classIDs: [Int32], features: [[[Double]]], timestamps: [[[Double]]],
                             maximumEpochs: Int32, store: inout Store) throws -> SaveResult {
        guard !classIDs.isEmpty, classIDs.count == features.count,
              classIDs.count == timestamps.count else { return .ignoredInvalidCounts }
        for index in classIDs.indices {
            let feature = features[index], time = timestamps[index], id = classIDs[index]
            if isEmpty(feature) || isEmpty(time) { continue }
            let incomingFeatures = try transpose(feature)
            let incomingTimes = try transpose(time)
            store.featureRows[id] = try appendRows(store.featureRows[id] ?? [], incomingFeatures)
            store.timestampRows[id] = try appendRows(store.timestampRows[id] ?? [], incomingTimes)
            let count = store.featureRows[id]!.count
            guard count == store.timestampRows[id]!.count else { throw InputError.epochCountMismatch }
            if maximumEpochs > 0, count > Int(maximumEpochs) {
                store.featureRows[id] = Array(store.featureRows[id]!.suffix(Int(maximumEpochs)))
                store.timestampRows[id] = Array(store.timestampRows[id]!.suffix(Int(maximumEpochs)))
            }
        }
        return .saved
    }

    private static func isEmpty(_ value: [[Double]]) -> Bool {
        value.isEmpty || value.first?.isEmpty == true
    }
    private static func validate(_ value: [[Double]]) throws {
        guard let columns = value.first?.count else { return }
        guard value.allSatisfy({ $0.count == columns && $0.allSatisfy(\.isFinite) }) else {
            throw InputError.invalidMatrix // Our shape/finite boundary, not vendor repair.
        }
    }
    private static func transpose(_ value: [[Double]]) throws -> [[Double]] {
        try validate(value)
        guard let columns = value.first?.count, columns > 0 else { return [] }
        return (0..<columns).map { column in value.map { $0[column] } }
    }
    private static func appendRows(_ previous: [[Double]], _ incoming: [[Double]]) throws -> [[Double]] {
        try validate(previous)
        if isEmpty(previous) { return incoming }
        guard previous.first!.count == incoming.first?.count else { throw InputError.columnMismatch }
        return previous + incoming
    }
}
