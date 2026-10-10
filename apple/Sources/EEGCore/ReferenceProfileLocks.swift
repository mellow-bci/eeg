import Foundation

/// Comparison-only advisory profile-key membership, not a mutex or write barrier.
/// ASCII keys are supported; QVariant equality is supplied by the caller rather than guessed.
struct ReferenceProfileLocks {
    enum Failure: Error { case invalidConfiguration, unsupportedKey, capacityExceeded }
    enum Event { case trainingStarted, trainingWaitingForAcceptReject, trainingCompleted, neutralSamplingStarted, neutralSamplingCompleted }
    struct WriteDisposition: Equatable {
        let writePermitted: Bool
        let emitLockedKeyDiagnostic: Bool
    }
    let maximumKeys: Int
    let maximumKeyBytes: Int
    private(set) var lockedKeys: Set<String> = []
    init(maximumKeys: Int, maximumKeyBytes: Int) throws {
        guard maximumKeys > 0, maximumKeyBytes > 0 else { throw Failure.invalidConfiguration }
        self.maximumKeys = maximumKeys; self.maximumKeyBytes = maximumKeyBytes
    }
    mutating func lock(_ key: String) throws {
        try validate(key)
        guard lockedKeys.contains(key) || lockedKeys.count < maximumKeys else { throw Failure.capacityExceeded }
        lockedKeys.insert(key) // Idempotent membership; no recursion count.
    }
    mutating func unlock(_ key: String) throws { try validate(key); lockedKeys.remove(key) }
    func disposition(for key: String, equalsPreviousQVariant: Bool) throws -> WriteDisposition {
        try validate(key)
        return WriteDisposition(writePermitted: true,
            emitLockedKeyDiagnostic: lockedKeys.contains(key) && !equalsPreviousQVariant)
    }
    /// These are only the observed per-key calls. No scheduler, training state or readiness is inferred.
    mutating func apply(_ event: Event) throws {
        let keys: [String]
        let adding: Bool
        switch event {
        case .trainingStarted: keys = Self.trainingKeys; adding = true
        case .trainingWaitingForAcceptReject: keys = ["cognitiv-trainingControl"]; adding = false
        case .trainingCompleted: keys = ["cognitiv-trainingControl"] + Self.trainingKeys; adding = false
        case .neutralSamplingStarted: keys = Self.neutralKeys; adding = true
        case .neutralSamplingCompleted: keys = Self.neutralKeys; adding = false
        }
        // Atomic capacity failure is our explicit bounded-support policy; vendor has no shown cap.
        var candidate = self
        for key in keys { if adding { try candidate.lock(key) } else { try candidate.unlock(key) } }
        self = candidate
    }
    private func validate(_ key: String) throws {
        guard key.utf8.count <= maximumKeyBytes, key.utf8.allSatisfy({ $0 < 128 }) else { throw Failure.unsupportedKey }
    }
    static let neutralKeys = ["cognitiv-trainingAction", "cognitiv-activeActions", "cognitiv-activationThreshold",
        "cognitiv-action1Threshold", "cognitiv-action2Threshold", "cognitiv-action3Threshold",
        "cognitiv-action4Threshold", "cognitiv-rebuildSignature"]
    static let trainingKeys = ["cognitiv-trainingAction", "cognitiv-autoSamplingNeutral"] + Array(neutralKeys.dropFirst())
}
