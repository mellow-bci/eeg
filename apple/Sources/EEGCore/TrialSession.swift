import Foundation

/// Single-executor trial lifecycle. Prepare and acknowledge on the owning executor;
/// storage may run elsewhere. A prepared revision is never a published label.
public final class EEGTrialSession {
    public enum Failure: Error { case activeTrial, persistenceUnavailable, pendingRevision, staleAcknowledgement }
    public struct Revision {
        public let id: UUID
        public let evidence: EEGTrialEvidence
        fileprivate let observedAt: Double?
    }
    public private(set) var trial: EEGTrialEvidence?
    public private(set) var persistenceFailure: String?
    public private(set) var pending: Revision?
    private let persist: (EEGTrialEvidence) throws -> Void
    /// Queued consumers prepare and acknowledge explicitly; synchronous calls
    /// without an installed sink fail instead of silently accepting evidence.
    public convenience init() {self.init(persist:{_ in throw Failure.persistenceUnavailable})}
    public init(persist: @escaping (EEGTrialEvidence) throws -> Void) { self.persist = persist }
    public var active: Bool {
        guard let trial else { return false }
        return trial.phase != .reviewed && trial.phase != .interrupted
    }
    public func prepareBegin(_ planned: EEGTrialEvidence) throws -> Revision {
        guard pending == nil else {throw Failure.pendingRevision}
        guard !active else {throw Failure.activeTrial}
        guard persistenceFailure == nil else {throw Failure.persistenceUnavailable}
        guard planned.phase == .planned else {throw EEGTrialEvidence.Failure.invalidTransition}
        let revision=Revision(id:UUID(),evidence:planned,observedAt:nil)
        pending=revision;return revision
    }
    public func prepareTransition(at:Double,_ change:(inout EEGTrialEvidence,Double)throws->Void) throws -> Revision {
        guard pending == nil else {throw Failure.pendingRevision}
        guard persistenceFailure == nil else {throw Failure.persistenceUnavailable}
        guard var next=trial else {throw EEGTrialEvidence.Failure.invalidTransition}
        try change(&next,at)
        let revision=Revision(id:UUID(),evidence:next,observedAt:at)
        pending=revision;return revision
    }
    /// Success acknowledges the exact pending revision only. Stale or duplicate
    /// callbacks cannot replace newer state or clear a persistence failure.
    public func acknowledge(_ revision:Revision,result:Result<Void,Error>) throws {
        guard pending?.id == revision.id else {throw Failure.staleAcknowledgement}
        pending=nil
        switch result {
        case .success: trial=revision.evidence
        case .failure(let error):
            persistenceFailure=error.localizedDescription
            if var interrupted=trial,active,let at=revision.observedAt {
                try? interrupted.interrupt(reason:"evidence_persistence_failed",at:at)
                trial=interrupted
            }
            throw error
        }
    }
    /// Invalidate publication immediately when pending I/O becomes uncertain.
    /// The host must abort the recording: the revision may already be on disk.
    /// This is an unpersisted interruption, never a successful revision save.
    public func invalidatePending(reason:String,at:Double) throws {
        guard pending != nil else {return}
        var interrupted=trial ?? pending!.evidence
        try interrupted.interrupt(reason:reason,at:at)
        pending=nil;persistenceFailure="Pending evidence invalidated: "+reason;trial=interrupted
    }
    // Synchronous consumers use the same prepare/acknowledge state transitions.
    private func commit(_ revision:Revision) throws {
        let result=Result {try persist(revision.evidence)}
        try acknowledge(revision,result:result)
    }
    public func begin(_ planned: EEGTrialEvidence) throws {try commit(prepareBegin(planned))}
    public func transition(at: Double, _ change: (inout EEGTrialEvidence, Double) throws -> Void) throws {
        try commit(prepareTransition(at:at,change))
    }
    public func interrupt(reason: String, at: Double) throws {
        if pending != nil {try invalidatePending(reason:reason,at:at);throw Failure.persistenceUnavailable}
        guard active else { return }
        try transition(at: at) { try $0.interrupt(reason: reason, at: $1) }
    }
}
