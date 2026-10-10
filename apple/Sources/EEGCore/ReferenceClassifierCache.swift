import Foundation

/// Pure comparison cache. Payloads are caller supplied; no profile/database serialization.
struct ReferenceClassifierCache<Payload> {
    struct Entry {
        let actions: [Int32]
        let payload: Payload
        var reuseCount: UInt64
    }
    enum InputError: Error { case actionMismatch, storageLimitExceeded, invalidStorageLimit }
    private(set) var isEnabled = true
    private(set) var maximumCacheSize: UInt64 = 0
    private(set) var entries: [String: Entry] = [:]
    let storageLimit: Int

    /// storageLimit is an independent safety bound; vendor maximum zero is uncapped.
    init(storageLimit: Int) throws {
        guard storageLimit > 0 else { throw InputError.invalidStorageLimit }
        self.storageLimit = storageLimit
    }
    static func key(_ actions: [Int32]) -> String { actions.map(String.init).joined(separator: ",") }
    mutating func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled { entries.removeAll() }
    }
    mutating func setMaximumCacheSize(_ size: UInt64) {
        maximumCacheSize = size
        entries.removeAll()
    }
    func get(_ actions: [Int32]) -> Entry? {
        guard isEnabled else { return nil }
        return entries[Self.key(actions)]
    }
    /// get itself does not update frequency. The manager increments on cache reuse.
    mutating func recordReuse(_ actions: [Int32]) -> Entry? {
        guard isEnabled, var entry = entries[Self.key(actions)] else { return nil }
        entry.reuseCount &+= 1
        entries[Self.key(actions)] = entry
        return entry
    }
    @discardableResult
    mutating func put(_ actions: [Int32], entry: Entry) throws -> Bool {
        guard isEnabled else { return false }
        guard entry.actions == actions else { throw InputError.actionMismatch }
        let key = Self.key(actions)
        var next = entries
        if next[key] == nil {
            if maximumCacheSize != 0 && UInt64(next.count) >= maximumCacheSize {
                // Ordered std::map traversal and strict-less comparison retain the
                // lexicographically first key when minimum counts tie.
                let victim = next.keys.sorted().min { a, b in
                    next[a]!.reuseCount < next[b]!.reuseCount
                }!
                next.removeValue(forKey: victim)
            }
            guard next.count < storageLimit else { throw InputError.storageLimitExceeded }
        }
        next[key] = entry
        entries = next
        return true
    }
    /// Called on the training action; removes every classifier containing that ID.
    /// The reference removal body does not gate on enabled state.
    mutating func removeDirtyClassifier(_ action: Int32) {
        entries = entries.filter { !$0.value.actions.contains(action) }
    }
}
