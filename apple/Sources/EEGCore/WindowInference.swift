import Foundation

public struct EEGWindowInferenceResult: Sendable, Equatable {
    public let ordinal: Int
    public let reasons: [String]
    public let candidate: String?
    public let firstSampleIndex: Int?
    public let lastSampleIndex: Int?
    public let sampleCount: Int
    public let inputStart: Double?
    public let inputEnd: Double?
    init(ordinal: Int, reasons: [String], candidate: String?, samples: [EEGSample]) {
        self.ordinal=ordinal;self.reasons=reasons;self.candidate=candidate
        firstSampleIndex=samples.first?.index;lastSampleIndex=samples.last?.index
        sampleCount=samples.count;inputStart=samples.first?.receivedAt;inputEnd=samples.last?.receivedAt
    }
    public let systemControlEnabled = false
    public let status = "no_reliable_command"
}

/// Shared sequential processing for canonically validated analysis windows.
/// Hosts own input ordering, overload handling and profile replacement. This
/// component has no device, recording, UI or system-action dependencies.
public struct EEGWindowInference {
    private var detector: EEGExperimentalDetector
    private let participantID: String
    private let sessionID: String
    public init(profile: EEGMentalProfile, participantID: String, sessionID: String) throws {
        guard participantID == profile.participantID,!sessionID.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw EEGReplayInference.Failure.invalidIdentity }
        self.participantID=participantID;self.sessionID=sessionID
        detector=try profile.makeDetector()
    }
    public mutating func reset() { detector.reset() }
    public mutating func process(_ window: EEGAnalysisWindow) -> EEGWindowInferenceResult {
        guard window.valid else {
            detector.reset()
            return .init(ordinal:window.ordinal,reasons:window.reasons,candidate:nil,samples:window.samples)
        }
        guard window.samples.count == 256,let segment=window.segment,
              let first=window.samples.first,let last=window.samples.last else {
            detector.reset()
            return .init(ordinal:window.ordinal,reasons:["invalid_analysis_window"],candidate:nil,samples:window.samples)
        }
        let features: EEGMentalFeatures
        do { features=try EEGMentalFeatures.extract(samples:window.samples) }
        catch {
            detector.reset()
            return .init(ordinal:window.ordinal,reasons:["feature_extraction_rejected"],candidate:nil,samples:window.samples)
        }
        let input=EEGInferenceWindow(values:features.values,feature_config_id:EEGMentalFeatures.configurationID,
            artifact_flags:features.artifactFlags,usable:features.usable,participant_id:participantID,
            session_id:sessionID,continuity_id:"segment-\(segment)",window_id:"\(sessionID):\(window.ordinal)",
            start:first.receivedAt,end:last.receivedAt)
        let proposal=detector.infer(input)
        return .init(ordinal:window.ordinal,reasons:features.artifactFlags.isEmpty ? [proposal.reason] : features.artifactFlags,
                     candidate:proposal.experimentalCandidate,samples:window.samples)
    }
}
