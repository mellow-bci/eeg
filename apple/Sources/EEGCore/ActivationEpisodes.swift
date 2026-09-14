import Foundation

public struct EEGConditionExposure: Sendable {
    public internal(set) var eligibleSeconds = 0.0
    public internal(set) var unarmedSeconds = 0.0
    public internal(set) var rejectedSeconds = 0.0
    public internal(set) var candidateWindows = 0
    public internal(set) var episodeOnsets = 0
    public internal(set) var carryInCandidates = 0
    /// Empirical rate only. No physiological validation or uncertainty bound implied.
    public var episodeOnsetsPerHour: Double? {
        eligibleSeconds > 0 && carryInCandidates == 0 ? Double(episodeOnsets) * 3600 / eligibleSeconds : nil
    }
}

/// Rising-edge accounting matches the independent Python evaluator. A candidate
/// carried into a new trial invalidates a clean onset-rate interpretation.
struct EEGActivationEpisodes {
    private struct Previous {
        let label: String?, session: String, trial: String, continuity: String
        let end: Double
    }
    private var previous: Previous?
    private(set) var conditions = [String: EEGConditionExposure]()
    mutating func consume(_ row: EEGTrainingDataset.EvaluationWindow, proposal: EEGExperimentalProposal?) throws {
        let input = row.input, duration = row.input.end - row.input.start
        guard duration.isFinite, duration > 0 else { throw EEGLabeledEvaluation.Failure.invalidTiming }
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
            else if !same { metrics.episodeOnsets += 1 }
        }
        conditions[row.condition] = metrics
        previous = Previous(label: label, session: input.session_id, trial: row.trialID, continuity: input.continuity_id, end: input.end)
    }
}
