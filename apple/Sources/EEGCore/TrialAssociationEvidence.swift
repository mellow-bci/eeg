import Foundation

extension EEGTrialPlanAssociation {
    public struct SourceResult: Encodable, Sendable {
        public let sourceFileSHA256: String
        public let minimumEligibleFraction: Double
        public let eligibleFractionsByTrialID: [String: Double]
        public let association: Result
    }
    public enum EvidenceFailure: String, Error {
        case invalidExposureSetting, sourceMismatch, unsupportedClasses, incompleteReviewedPlan
        case trialMismatch, invalidExposure, insufficientExposure
    }

    public static func validateMinimumEligibleFraction(_ fraction: Double) throws {
        guard fraction.isFinite, fraction > 0, fraction <= 1 else { throw EvidenceFailure.invalidExposureSetting }
    }
    public struct Assessment: Encodable, Sendable {
        public let status: String
        public let reason: String?
        public let expectedSourceFileSHA256: String
        public let minimumEligibleFraction: Double
        public let result: SourceResult?
        public var explanation: String {
            switch reason {
            case "missing_native_trial_plan": return "No native trial plan was recorded."
            case "unsupportedClasses": return "Requires neutral and silent serial subtraction classes."
            case "incompleteReviewedPlan": return "All 24 planned trials must be completed, accepted and reviewed."
            case "trialMismatch": return "Evaluated trials do not match the recorded plan and cue timing."
            case "invalidExposure": return "Trial exposure or candidate counts are inconsistent."
            case "insufficientExposure": return "At least one trial falls below the selected usable-exposure threshold."
            default: return result == nil ? "Required comparison evidence is unavailable." : "Conditional association only; exchangeability is unverified."
            }
        }
    }
    static func assess(store: EEGRecordingStore, dataset: EEGTrainingDataset, report: EEGLabeledEvaluation,
                       minimumEligibleFraction: Double) throws -> [String: Assessment] {
        try validateMinimumEligibleFraction(minimumEligibleFraction)
        var assessments = [String: Assessment]()
        for session in dataset.sessions where session.split == "evaluation" {
            try Task.checkCancellation()
            guard let name = session.recordingName else { throw EvidenceFailure.sourceMismatch }
            var result: SourceResult?, reason: String?
            do {
                result = try run(recording: store.directory.appendingPathComponent(name), store: store,
                    expectedFileSHA256: session.fileSHA256, participantID: dataset.participantID,
                    sessionID: session.id, classes: Array(report.metrics.keys),
                    trials: report.trials.filter { $0.sessionID == session.id }, minimumEligibleFraction: minimumEligibleFraction)
            } catch EEGRecordingError.missingTrialPlan(let hash) {
                guard hash == session.fileSHA256 else { throw EvidenceFailure.sourceMismatch }
                reason = "missing_native_trial_plan"
            } catch let failure as EvidenceFailure {
                // Stale/mismatched sources cannot publish an evaluation receipt.
                if failure == .sourceMismatch { throw failure }
                reason = failure.rawValue
            }
            assessments[session.id] = Assessment(status: result == nil ? "unavailable" : "conditional_only_exchangeability_unverified",
                reason: reason, expectedSourceFileSHA256: session.fileSHA256,
                minimumEligibleFraction: minimumEligibleFraction, result: result)
        }
        return assessments
    }

    /// Internal adapter for canonical evaluator outputs, not arbitrary caller-
    /// supplied Boolean outcomes. Source digest must come from that evaluation.
    /// All checks complete before a conditional comparison can be returned.
    static func run(recording: URL, store: EEGRecordingStore, expectedFileSHA256: String,
                    participantID: String, sessionID: String, classes: [String],
                    trials: [EEGTrialTiming], minimumEligibleFraction: Double) throws -> SourceResult {
        try Task.checkCancellation()
        try validateMinimumEligibleFraction(minimumEligibleFraction)
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
