import Foundation

/// Pure body-derived ErrorSetClassifierBank comparison contract. Not database persistence.
struct ReferenceErrorSetCache<Payload> {
    enum Failure: Error { case invalidStorageLimit, storageCapacityExceeded, nullClassifier, actionMismatch }
    /// Models shared classifier identity: mutations after lookup remain visible to the cache.
    final class Entry {
        let actions: [Int32]
        var reuseCount: UInt64
        var payload: Payload
        init(actions: [Int32], reuseCount: UInt64 = 0, payload: Payload) {
            self.actions = actions; self.reuseCount = reuseCount; self.payload = payload
        }
    }
    private(set) var entries: [String: Entry] = [:]
    private(set) var maximumClassifiers: UInt64 = 0
    let storageLimit: Int
    init(storageLimit: Int) throws {
        guard storageLimit > 0 else { throw Failure.invalidStorageLimit }
        self.storageLimit = storageLimit
    }
    static func key(actions: [Int32], channels: [UInt64]) -> String {
        actions.map(String.init).joined(separator: ",") + ":" + channels.map(String.init).joined(separator: ",")
    }
    mutating func clear() { entries.removeAll() }
    /// Always clears, even if unchanged. Vendor zero is uncapped; storageLimit remains our guard.
    mutating func setMaximumClassifiers(_ maximum: UInt64) {
        maximumClassifiers = maximum; clear()
    }
    func get(actions: [Int32], channels: [UInt64]) throws -> Entry? {
        guard let entry = entries[Self.key(actions: actions, channels: channels)] else { return nil }
        guard entry.actions == actions else { throw Failure.actionMismatch }
        return entry
    }
    mutating func put(actions: [Int32], channels: [UInt64], entry: Entry?) throws {
        guard let entry else { throw Failure.nullClassifier }
        let key = Self.key(actions: actions, channels: channels)
        if entries[key] == nil {
            if maximumClassifiers != 0, UInt64(entries.count) >= maximumClassifiers {
                // Ordered map iteration retains first entry on equal count.
                if let victim = entries.keys.sorted().min(by: {
                    let lhs = entries[$0]!.reuseCount, rhs = entries[$1]!.reuseCount
                    return lhs == rhs ? $0 < $1 : lhs < rhs
                }) { entries.removeValue(forKey: victim) }
            } else if entries.count >= storageLimit { throw Failure.storageCapacityExceeded }
        }
        entries[key] = entry
    }
}
