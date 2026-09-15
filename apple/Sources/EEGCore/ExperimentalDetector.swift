import Foundation

/// Versioned feature-window input. Validity/provenance must be established by
/// canonical window extraction; decoding JSON does not establish that evidence.
public struct EEGInferenceWindow: Decodable, Sendable {
    public let values: [Double]
    public let feature_config_id: String
    public let artifact_flags: [String]
    public let usable: Bool
    public let participant_id: String
    public let session_id: String
    public let continuity_id: String
    public let window_id: String
    public let start: Double
    public let end: Double
}

public struct EEGExperimentalProposal: Sendable {
    public let profileID: String
    public let windowID: String
    public let reason: String
    public let experimentalCandidate: String?
    public let evidenceStart: Double?
    public let uncalibratedScores: [Double]?
    public let status = "no_reliable_command"
    public let systemControlEnabled = false
    public var command: String? { nil }
}

/// Sequential, value-semantic detector state. The caller serializes inference.
/// Not a profile loader: persistent profile integrity checks remain a separate gate.
public struct EEGExperimentalDetector {
    private let parameters: EEGMentalScoringParameters
    private let settings: ProcessingSettings
    private let participantID: String
    private let profileID: String
    private var session: String?
    private var continuity: String?
    private var lastEnd: Double?
    private var pending: String?
    private var count = 0
    private var evidenceStart: Double?

    public init(parameters: EEGMentalScoringParameters, settings: ProcessingSettings,
                participantID: String, profileID: String) throws {
        try settings.validate()
        guard !participantID.isEmpty, !profileID.isEmpty else { throw EEGMentalScoringError.invalidParameters }
        // Validate transform structure without requiring arbitrary zero inputs to
        // be numerically representable under a valid but extreme model.
        _ = try EEGMentalScoring.score(values: parameters.center, parameters: parameters)
        self.parameters = parameters; self.settings = settings
        self.participantID = participantID; self.profileID = profileID
    }
    public mutating func reset() {
        session = nil; continuity = nil; lastEnd = nil
        pending = nil; count = 0; evidenceStart = nil
    }
    public mutating func infer(_ window: EEGInferenceWindow) -> EEGExperimentalProposal {
        func output(_ reason: String, candidate: String? = nil, start: Double? = nil, scores: [Double]? = nil) -> EEGExperimentalProposal {
            EEGExperimentalProposal(profileID: profileID, windowID: window.window_id, reason: reason,
                                    experimentalCandidate: candidate, evidenceStart: start, uncalibratedScores: scores)
        }
        var invalid: String?
        if window.feature_config_id != EEGMentalFeatures.configurationID { invalid = "feature_configuration_mismatch" }
        else if !window.usable || !window.artifact_flags.isEmpty { invalid = "invalid_or_artifact_window" }
        else if window.participant_id != participantID { invalid = "participant_mismatch" }
        else if window.session_id.isEmpty || window.window_id.isEmpty { invalid = "missing_recording_identity" }
        else if window.continuity_id.isEmpty { invalid = "missing_continuity_identity" }
        else if !window.start.isFinite || window.start < 0 || !window.end.isFinite || window.end <= window.start { invalid = "invalid_timing" }
        if let invalid { reset(); return output(invalid) }
        if session == window.session_id, continuity == window.continuity_id,
           let previousEnd = lastEnd, window.start < previousEnd {
            reset()
            return output("overlapping_or_reordered_window")
        }
        if session != window.session_id || continuity != window.continuity_id || lastEnd == nil || abs(window.start - (lastEnd ?? 0)) > 0.05 {
            reset()
        }
        session = window.session_id; continuity = window.continuity_id; lastEnd = window.end
        let score: EEGMentalScore
        do { score = try EEGMentalScoring.score(values: window.values, parameters: parameters) }
        catch {
            reset()
            return output((error as? EEGMentalScoringError) == .invalidFeatures ? "invalid_features" : "numerical_failure")
        }
        let ordered = score.uncalibratedScores.sorted(by: >)
        var reason: String?
        if score.outsideTrainingDistribution { reason = "out_of_training_distribution" }
        else if ordered[0] < settings.scoreThreshold || ordered[0] - ordered[1] < settings.marginThreshold { reason = "ambiguous_score" }
        else if score.candidateLabel == "neutral" { reason = "neutral" }
        if let reason { reset(); return output(reason, scores: score.uncalibratedScores) }
        if pending == score.candidateLabel { if count < settings.persistenceWindows { count += 1 } }
        else { count = 1; evidenceStart = window.start; pending = score.candidateLabel }
        guard count >= settings.persistenceWindows else { return output("insufficient_persistence", scores: score.uncalibratedScores) }
        return output("profile_not_hardware_validated", candidate: score.candidateLabel,
                      start: evidenceStart, scores: score.uncalibratedScores)
    }
}
