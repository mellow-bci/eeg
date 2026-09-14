import Foundation

/// Independent implementation of eeg.silent-subtraction-neutral.v1 evidence rules.
/// The controller supplies actual playback callbacks and recording-clock times.
/// This type does not play audio, acquire EEG, infer compliance or enable commands.
public struct EEGTrialEvidence: Encodable, Sendable {
    public enum Condition: String, Encodable, Sendable { case neutral, silentSerialSubtraction = "silent_serial_subtraction" }
    public enum Phase: String, Encodable, Sendable {
        case planned, cueRequested, cuePlaying, conditionActive, endRequested, endPlaying, awaitingReport, reported, reviewed, interrupted
    }
    public enum ParticipantReport: String, Encodable, Sendable { case attempted, uncertain, notAttempted, missedCue }
    public enum Failure: Error { case invalidIdentity, invalidTransition, invalidTime, readinessMissing, invalidReview, notAccepted }
    public struct Event: Encodable, Sendable {
        public let kind: String
        public let at: Double
        public let detail: String?
    }
    public struct DatasetTrial: Encodable, Sendable {
        public let id: String, label: String
        public let start: Double, end: Double
        public let accepted: Bool, label_verified: Bool
        public let condition: String
        public let shadow_enabled: Bool
        public let cue_completed_at: Double
    }
    public let schema = "eeg.trial-evidence.v1"
    public let protocolID = "eeg.silent-subtraction-neutral.v1"
    public let timeBasis = "recorded_receipt_seconds"
    public let id: String, sessionID: String, participantID: String
    public let requestedCondition: Condition
    public let startingNumber: Int
    public private(set) var phase: Phase = .planned
    public private(set) var events: [Event] = []
    public private(set) var cueCompletedAt: Double?
    public private(set) var participantReport: ParticipantReport?
    public private(set) var observedBehavior = "unknown"
    public private(set) var reviewer: String?
    public private(set) var reviewReason: String?
    public private(set) var accepted = false
    public let labelMeaning = "operator-reviewed reported task condition; not neural ground truth"

    public init(id: String, sessionID: String, participantID: String, condition: Condition, startingNumber: Int) throws {
        guard [id, sessionID, participantID].allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              (100...999).contains(startingNumber) else { throw Failure.invalidIdentity }
        self.id = id; self.sessionID = sessionID; self.participantID = participantID
        requestedCondition = condition; self.startingNumber = startingNumber
    }
    public var conditionDeadline: Double? { cueCompletedAt.map { $0 + 20 } }
    private func checkTime(_ at: Double) throws {
        guard at.isFinite, at >= 0, at >= (events.last?.at ?? 0) else { throw Failure.invalidTime }
    }
    private mutating func event(_ kind: String, at: Double, detail: String? = nil) {
        events.append(Event(kind: kind, at: at, detail: detail))
    }
    public mutating func requestCue(at: Double, participantReady: Bool, audioCheckHeard: Bool,
                                    transportStable: Bool, recordingActive: Bool) throws {
        guard phase == .planned else { throw Failure.invalidTransition }
        try checkTime(at)
        guard participantReady, audioCheckHeard, transportStable, recordingActive else { throw Failure.readinessMissing }
        event("cue_requested", at: at, detail: "fresh readiness and heard-check declared; stable recording asserted")
        phase = .cueRequested
    }
    public mutating func cueStarted(at: Double) throws {
        guard phase == .cueRequested else { throw Failure.invalidTransition }
        try checkTime(at); event("cue_playback_started", at: at); phase = .cuePlaying
    }
    public mutating func cueCompleted(at: Double) throws {
        guard phase == .cuePlaying else { throw Failure.invalidTransition }
        try checkTime(at)
        guard (at + 20).isFinite, at + 5 > at, at + 17 > at + 5 else { throw Failure.invalidTime }
        cueCompletedAt = at; event("cue_playback_completed", at: at); phase = .conditionActive
    }
    public mutating func requestEndCue(at: Double) throws {
        guard phase == .conditionActive, let deadline = conditionDeadline else { throw Failure.invalidTransition }
        try checkTime(at)
        guard at >= deadline else { throw Failure.invalidTime }
        event("end_cue_requested", at: at); phase = .endRequested
    }
    public mutating func endCueStarted(at: Double) throws {
        guard phase == .endRequested else { throw Failure.invalidTransition }
        try checkTime(at); event("end_cue_playback_started", at: at); phase = .endPlaying
    }
    public mutating func endCueCompleted(at: Double) throws {
        guard phase == .endPlaying else { throw Failure.invalidTransition }
        try checkTime(at); event("end_cue_playback_completed", at: at); phase = .awaitingReport
    }
    public mutating func report(_ report: ParticipantReport, at: Double, observedBehavior: String = "unknown") throws {
        guard phase == .awaitingReport else { throw Failure.invalidTransition }
        try checkTime(at)
        guard !observedBehavior.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.invalidReview }
        participantReport = report; self.observedBehavior = observedBehavior
        event("participant_report", at: at, detail: report.rawValue); phase = .reported
    }
    public mutating func review(accept: Bool, reviewer: String, reason: String, at: Double) throws {
        guard phase == .reported else { throw Failure.invalidTransition }
        try checkTime(at)
        guard !reviewer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !accept || participantReport == .attempted else { throw Failure.invalidReview }
        self.reviewer = reviewer; reviewReason = reason; accepted = accept
        event("operator_review", at: at, detail: reason); phase = .reviewed
    }
    public mutating func interrupt(reason: String, at: Double) throws {
        guard phase != .reviewed, phase != .interrupted else { throw Failure.invalidTransition }
        try checkTime(at)
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.invalidReview }
        accepted = false; reviewReason = reason
        event("interrupted", at: at, detail: reason); phase = .interrupted
    }
    public func datasetTrial() throws -> DatasetTrial {
        guard phase == .reviewed, accepted, let cue = cueCompletedAt else { throw Failure.notAccepted }
        return DatasetTrial(id: id, label: requestedCondition.rawValue, start: cue + 5, end: cue + 17,
            accepted: true, label_verified: true, condition: requestedCondition == .neutral ? "cued_neutral" : "cued_task",
            shadow_enabled: true, cue_completed_at: cue)
    }
}
