import Foundation

public struct EEGLabeledEvaluation: Sendable {
    public struct Metric: Sendable {
        public let truePositive: Int, falsePositive: Int, falseNegative: Int, rejectedWindows: Int
        public var actualWindows: Int { truePositive + falseNegative }
        public var rejectionFraction: Double? { actualWindows > 0 ? Double(rejectedWindows) / Double(actualWindows) : nil }
        public var precision: Double? { truePositive + falsePositive > 0 ? Double(truePositive) / Double(truePositive + falsePositive) : nil }
        public var recall: Double? { truePositive + falseNegative > 0 ? Double(truePositive) / Double(truePositive + falseNegative) : nil }
    }
    public struct Prediction: Sendable {
        public let windowID: String, sessionID: String, trialID: String, actual: String
        public let predictedLabel: String?
        public let reason: String
        public let inputUsable: Bool
    }
    public var sessionMetrics: [String: [String: Metric]] {
        Dictionary(grouping: predictions, by: \.sessionID).mapValues { Self.summarize($0,classes:Array(metrics.keys)) }
    }
    static func summarize(_ predictions: [Prediction], classes: [String]) -> [String: Metric] {
        var result = [String: Metric]()
        for label in classes {
            result[label] = Metric(truePositive: predictions.filter { $0.actual == label && $0.predictedLabel == label }.count,
                falsePositive: predictions.filter { $0.actual != label && $0.predictedLabel == label }.count,
                falseNegative: predictions.filter { $0.actual == label && $0.predictedLabel != label }.count,
                rejectedWindows: predictions.filter { $0.actual == label && $0.predictedLabel == nil }.count)
        }
        return result
    }
    public let controlsOnly: Bool
    public let profileID: String
    public let predictions: [Prediction]
    public let metrics: [String: Metric]
    public let trials: [EEGTrialTiming]
    public let conditions: [String: EEGConditionExposure]
    public let sessionConditions: [String: [String: EEGConditionExposure]]
    /// Presence check only, not a duration or physiological qualification gate.
    public var controlConditionsWithoutEligibleExposure: [String] {
        ["ordinary_activity", "blink_control", "jaw_control", "head_movement_control"].filter {
            (conditions[$0]?.eligibleSeconds ?? 0) <= 0
        }
    }
    public let systemControlEnabled = false
    public let hardwareValidated = false
    public var rejectionFraction: Double { Double(predictions.filter { $0.predictedLabel == nil }.count) / Double(predictions.count) }
    public enum Failure: Error { case noEvaluation, participantMismatch, trainingOverlap, insufficientClassWindows, invalidLabels, invalidTiming }

    /// Window-level experimental metrics only. Correlated windows are not
    /// independent physiological trials. Rejection is never a neutral prediction.
    public static func run(profile: EEGMentalProfile, dataset: EEGTrainingDataset, controlsOnly: Bool = false) throws -> EEGLabeledEvaluation {
        guard dataset.participantID == profile.participantID else { throw Failure.participantMismatch }
        guard !dataset.evaluation.isEmpty else { throw Failure.noEvaluation }
        let sessions = dataset.sessions.filter { $0.split == "evaluation" }
        guard sessions.allSatisfy({ !profile.trainingSessions.contains($0.id) && !profile.trainingRecordingHashes.values.contains($0.eegSHA256) }) else { throw Failure.trainingOverlap }
        if controlsOnly {
            let controls = ["cued_neutral", "ordinary_activity", "blink_control", "jaw_control", "head_movement_control"]
            guard dataset.evaluation.allSatisfy({ $0.label == "neutral" && controls.contains($0.condition) }) else { throw Failure.invalidLabels }
        }
        for label in (controlsOnly ? [] : profile.parameters.classes) {
            guard dataset.evaluation.filter({ $0.label == label }).count >= 10 else { throw Failure.insufficientClassWindows }
        }
        var detector = try profile.makeDetector(), predictions = [Prediction](), lastEnd = [String: Double]()
        var episodes = EEGActivationEpisodes()
        for row in dataset.evaluation {
            let input = row.input
            guard profile.parameters.classes.contains(row.label) else { throw Failure.invalidLabels }
            guard input.start.isFinite, input.end.isFinite, input.end > input.start,
                  input.start >= (lastEnd[input.session_id] ?? -.infinity) else { throw Failure.invalidTiming }
            lastEnd[input.session_id] = input.end
            let proposal: EEGExperimentalProposal?
            if row.shadowEnabled { proposal = detector.infer(input) }
            else { detector.reset(); proposal = nil }
            try episodes.consume(row, proposal: proposal)
            let predicted = proposal?.experimentalCandidate ?? (proposal?.reason == "neutral" ? "neutral" : nil)
            predictions.append(Prediction(windowID: input.window_id, sessionID: input.session_id, trialID: row.trialID,
                actual: row.label, predictedLabel: predicted, reason: proposal?.reason ?? "shadow_disabled", inputUsable: input.usable))
        }
        let metrics = summarize(predictions, classes: profile.parameters.classes)
        return EEGLabeledEvaluation(controlsOnly: controlsOnly, profileID: profile.id, predictions: predictions, metrics: metrics, trials: episodes.trials, conditions: episodes.conditions, sessionConditions: episodes.sessionConditions)
    }
}
