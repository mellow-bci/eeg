import Foundation

/// Single-thread-owned trial lifecycle. The host serializes calls with acquisition.
/// A transition is published only after the recording sink accepts it. A failed
/// sink leaves an explicitly unpersisted interruption, never an accepted label.
public final class EEGTrialSession {
    public enum Failure: Error { case activeTrial, persistenceUnavailable }
    public private(set) var trial: EEGTrialEvidence?
    public private(set) var persistenceFailure: String?
    private let persist: (EEGTrialEvidence) throws -> Void
    public init(persist: @escaping (EEGTrialEvidence) throws -> Void) { self.persist = persist }
    public var active: Bool {
        guard let trial else { return false }
        return trial.phase != .reviewed && trial.phase != .interrupted
    }
    public func begin(_ planned: EEGTrialEvidence) throws {
        guard !active else { throw Failure.activeTrial }
        guard persistenceFailure == nil else { throw Failure.persistenceUnavailable }
        guard planned.phase == .planned else { throw EEGTrialEvidence.Failure.invalidTransition }
        do { try persist(planned); trial = planned }
        catch { persistenceFailure = error.localizedDescription; throw error }
    }
    public func transition(at: Double, _ change: (inout EEGTrialEvidence, Double) throws -> Void) throws {
        guard persistenceFailure == nil else { throw Failure.persistenceUnavailable }
        guard var next = trial else { throw EEGTrialEvidence.Failure.invalidTransition }
        try change(&next, at)
        do { try persist(next); trial = next }
        catch {
            persistenceFailure = error.localizedDescription
            // Keep the last durable revision as the basis for interruption. The
            // failed transition might have reached disk; do not retry this sink.
            if var interrupted = trial, active {
                try? interrupted.interrupt(reason: "evidence_persistence_failed", at: at)
                trial = interrupted
            }
            throw error
        }
    }
    public func interrupt(reason: String, at: Double) throws {
        guard active else { return }
        try transition(at: at) { try $0.interrupt(reason: reason, at: $1) }
    }
}
