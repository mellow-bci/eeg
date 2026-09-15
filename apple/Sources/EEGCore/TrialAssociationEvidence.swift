import Foundation

extension EEGTrialPlanAssociation {
    public struct SourceResult: Encodable, Sendable {
        public let sourceFileSHA256: String
        public let minimumEligibleFraction: Double
        public let eligibleFractionsByTrialID: [String: Double]
        public let association: Result
    }
    public enum EvidenceFailure: Error {
        case invalidExposureSetting, sourceMismatch, unsupportedClasses, incompleteReviewedPlan
        case trialMismatch, invalidExposure, insufficientExposure
    }

    /// Internal adapter for canonical evaluator outputs, not arbitrary caller-
    /// supplied Boolean outcomes. Source digest must come from that evaluation.
    /// All checks complete before a conditional comparison can be returned.
    static func run(recording: URL, store: EEGRecordingStore, expectedFileSHA256: String,
                    participantID: String, sessionID: String, classes: [String],
                    trials: [EEGTrialTiming], minimumEligibleFraction: Double) throws -> SourceResult {
        try Task.checkCancellation()
        guard minimumEligibleFraction.isFinite, minimumEligibleFraction > 0,
              minimumEligibleFraction <= 1 else { throw EvidenceFailure.invalidExposureSetting }
        guard classes.count == 2, Set(classes) == Set(["neutral", "silent_serial_subtraction"]) else {
            throw EvidenceFailure.unsupportedClasses
        }
        let source = try store.recoverTrialRecording(recording: recording)
        guard source.fileSHA256 == expectedFileSHA256,
              source.plan.trials.allSatisfy({ $0.participantID == participantID && $0.sessionID == sessionID }) else {
            throw EvidenceFailure.sourceMismatch
        }
        guard source.plan.controlProtocol == nil, source.trials.count == 24,
              source.trials.allSatisfy({ $0.phase == .reviewed && $0.accepted && $0.participantReport == .attempted }) else {
            throw EvidenceFailure.incompleteReviewedPlan
        }
        guard trials.count == 24, Set(trials.map(\.trialID)).count == 24,
              Set(trials.map(\.trialID)) == Set(source.trials.map(\.id)),
              trials.allSatisfy({ $0.sessionID == sessionID }) else { throw EvidenceFailure.trialMismatch }
        let timings = Dictionary(uniqueKeysWithValues: trials.map { ($0.trialID, $0) })
        var outcomes = [String: Bool](), fractions = [String: Double]()
        for evidence in source.trials {
            try Task.checkCancellation()
            let declared = try evidence.datasetTrial(), timing = timings[evidence.id]!
            guard timing.label == declared.label, timing.condition == declared.condition,
                  timing.start == declared.start, timing.end == declared.end,
                  timing.cueCompletedAt == declared.cue_completed_at else { throw EvidenceFailure.trialMismatch }
            let duration = timing.end - timing.start
            // Only accommodate addition roundoff; never treat packet gaps as covered.
            let tolerance = duration * 1e-12
            guard timing.coveredSeconds.isFinite, timing.eligibleSeconds.isFinite,
                  timing.eligibleSeconds >= 0, timing.coveredSeconds >= 0,
                  timing.eligibleSeconds <= timing.coveredSeconds + tolerance,
                  timing.coveredSeconds <= duration + tolerance,
                  timing.containedCandidateWindows >= 0, timing.containedTargetWindows >= 0,
                  (timing.label == "neutral" ? timing.containedTargetWindows == 0 :
                    timing.containedTargetWindows == timing.containedCandidateWindows),
                  timing.containedCandidateWindows == 0 || timing.eligibleSeconds > 0 else {
                throw EvidenceFailure.invalidExposure
            }
            let fraction = min(1, timing.eligibleSeconds / duration)
            guard fraction >= minimumEligibleFraction else { throw EvidenceFailure.insufficientExposure }
            fractions[evidence.id] = fraction
            outcomes[evidence.id] = timing.containedCandidateWindows > 0
        }
        return SourceResult(sourceFileSHA256: source.fileSHA256, minimumEligibleFraction: minimumEligibleFraction,
            eligibleFractionsByTrialID: fractions, association: try run(plan: source.plan, candidateObserved: outcomes))
    }
}
