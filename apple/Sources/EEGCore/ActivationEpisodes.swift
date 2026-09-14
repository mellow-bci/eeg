import Foundation

public struct EEGConditionExposure: Sendable {
    public internal(set) var eligibleSeconds = 0.0
    public internal(set) var unarmedSeconds = 0.0
    public internal(set) var rejectedSeconds = 0.0
    public internal(set) var candidateWindows = 0
    public internal(set) var episodeOnsets = 0
    public internal(set) var carryInCandidates = 0
    public var poissonUpper95PerHour: Double? {
        guard eligibleSeconds.isFinite, eligibleSeconds > 0, carryInCandidates == 0,
              let countBound = EEGPoissonBound.upper95(count: episodeOnsets) else { return nil }
        let rate = countBound * 3600 / eligibleSeconds
        return rate.isFinite ? rate : nil
    }
    /// Empirical rate only; no physiological validation implied.
    public var episodeOnsetsPerHour: Double? {
        eligibleSeconds > 0 && carryInCandidates == 0 ? Double(episodeOnsets) * 3600 / eligibleSeconds : nil
    }
}

public struct EEGTrialTiming: Sendable {
    public let sessionID: String, trialID: String, label: String, condition: String
    public let start: Double, end: Double, cueCompletedAt: Double?
    public internal(set) var coveredSeconds = 0.0
    public internal(set) var firstCueAssociatedCandidateLatency: Double? = nil
    public var unobservedSeconds: Double { max(0, end - start - coveredSeconds) }
    public var cuedTargetDetected: Bool? {
        condition == "cued_task" && cueCompletedAt != nil ? firstCueAssociatedCandidateLatency != nil : nil
    }
}

/// Rising-edge accounting matches the independent Python evaluator. A candidate
/// carried into a new trial invalidates a clean onset-rate interpretation.
struct EEGActivationEpisodes {
    private struct Previous {
        let label: String?, session: String, trial: String, continuity: String
        let end: Double
    }
    private struct TrialKey: Hashable { let session: String, trial: String }
    private var trialStorage = [TrialKey: EEGTrialTiming]()
    private var trialOrder = [TrialKey]()
    var trials: [EEGTrialTiming] { trialOrder.compactMap { trialStorage[$0] } }
    private var previous: Previous?
    private(set) var conditions = [String: EEGConditionExposure]()
    mutating func consume(_ row: EEGTrainingDataset.EvaluationWindow, proposal: EEGExperimentalProposal?) throws {
        let input = row.input, duration = row.input.end - row.input.start
        guard duration.isFinite, duration > 0 else { throw EEGLabeledEvaluation.Failure.invalidTiming }
        guard row.trialStart.isFinite, row.trialEnd.isFinite, row.trialEnd > row.trialStart,
              input.start >= row.trialStart, input.end <= row.trialEnd else { throw EEGLabeledEvaluation.Failure.invalidTiming }
        if let cue = row.cueCompletedAt { guard cue.isFinite, cue <= row.trialEnd else { throw EEGLabeledEvaluation.Failure.invalidTiming } }
        let key = TrialKey(session: input.session_id, trial: row.trialID)
        var trial = trialStorage[key] ?? EEGTrialTiming(sessionID: input.session_id, trialID: row.trialID,
            label: row.label, condition: row.condition, start: row.trialStart, end: row.trialEnd, cueCompletedAt: row.cueCompletedAt)
        guard trial.start == row.trialStart, trial.end == row.trialEnd, trial.label == row.label,
              trial.condition == row.condition, trial.cueCompletedAt == row.cueCompletedAt else { throw EEGLabeledEvaluation.Failure.invalidTiming }
        trial.coveredSeconds += duration
        var metrics = conditions[row.condition] ?? EEGConditionExposure()
        if !row.shadowEnabled { metrics.unarmedSeconds += duration }
        else if !input.usable { metrics.rejectedSeconds += duration }
        else { metrics.eligibleSeconds += duration }
        let label = row.shadowEnabled && input.usable ? proposal?.experimentalCandidate : nil
        if let label {
            guard let start = proposal?.evidenceStart, start.isFinite, start <= input.start,
                  !input.continuity_id.isEmpty else { throw EEGLabeledEvaluation.Failure.invalidTiming }
            metrics.candidateWindows += 1
            let same = previous.map { $0.label == label && $0.session == input.session_id &&
                $0.continuity == input.continuity_id && input.start - $0.end >= 0 && input.start - $0.end <= 0.05 } ?? false
            if (!same && start < row.trialStart) || (same && previous?.trial != row.trialID) { metrics.carryInCandidates += 1 }
            else if !same {
                metrics.episodeOnsets += 1
                if row.condition == "cued_task", label == row.label, let cue = row.cueCompletedAt,
                   start >= cue, trial.firstCueAssociatedCandidateLatency == nil {
                    trial.firstCueAssociatedCandidateLatency = input.end - cue
                }
            }
        }
        if trialStorage[key] == nil { trialOrder.append(key) }
        trialStorage[key] = trial
        conditions[row.condition] = metrics
        previous = Previous(label: label, session: input.session_id, trial: row.trialID, continuity: input.continuity_id, end: input.end)
    }
}
