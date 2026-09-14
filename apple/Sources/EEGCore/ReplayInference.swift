import Foundation

/// Offline diagnostics only. Neither candidates nor score values authorize actions.
public struct EEGReplayInferenceReport: Sendable {
    public struct Window: Sendable {
        public let ordinal: Int
        public let reasons: [String]
        public let candidate: String?
    }
    public let profileID: String
    public let recordingSHA256: String
    public let eegContentSHA256: String
    public let participantID: String
    public let sessionID: String
    public let windows: [Window]
    public let systemControlEnabled = false
    public let status = "experimental_unvalidated"
}

public enum EEGReplayInference {
    public enum Failure: Error, LocalizedError {
        case invalidIdentity, trainingRecording, windowLimitExceeded, invalidLimit
        public var errorDescription: String? {
            switch self {
            case .invalidIdentity: return "Enter the profile participant and a nonempty session identity."
            case .trainingRecording: return "This session or exact recording content was used for training. Choose a separate recording."
            case .windowLimitExceeded: return "The recording exceeds the configured window limit. Increase it to process the complete recording."
            case .invalidLimit: return "The window limit must be positive."
            }
        }
    }

    /// Caller supplies asserted participant/session identity; this does not verify
    /// who wore the headset. Returns only after the entire recording is validated.
    /// No labels or accuracy metrics are fabricated from experimental candidates.
    public static func run(store: EEGRecordingStore, recording: URL, profile: EEGMentalProfile,
                           participantID: String, sessionID: String,
                           maximumWindows: Int = 10000) throws -> EEGReplayInferenceReport {
        guard maximumWindows > 0 else { throw Failure.invalidLimit }
        guard participantID == profile.participantID, !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.invalidIdentity }
        guard !profile.trainingSessions.contains(sessionID) else { throw Failure.trainingRecording }
        var detector = try profile.makeDetector()
        var rows = [EEGReplayInferenceReport.Window]()
        var fingerprint = EEGRecordingFingerprint()
        let digest = try store.analysisWindows(recording: recording) { window in
            for sample in window.samples { try fingerprint.append(sample) }
            guard rows.count < maximumWindows else { throw Failure.windowLimitExceeded }
            if !window.valid {
                detector.reset()
                rows.append(.init(ordinal: window.ordinal, reasons: window.reasons, candidate: nil))
                return
            }
            let features: EEGMentalFeatures
            do { features = try EEGMentalFeatures.extract(samples: window.samples) }
            catch {
                detector.reset()
                rows.append(.init(ordinal: window.ordinal, reasons: ["feature_extraction_rejected"], candidate: nil))
                return
            }
            let input = EEGInferenceWindow(values: features.values, feature_config_id: EEGMentalFeatures.configurationID,
                artifact_flags: features.artifactFlags, usable: features.usable, participant_id: participantID,
                session_id: sessionID, continuity_id: "segment-\(window.segment!)",
                window_id: "\(sessionID):\(window.ordinal)", start: window.samples.first!.receivedAt,
                end: window.samples.last!.receivedAt)
            let proposal = detector.infer(input)
            rows.append(.init(ordinal: window.ordinal,
                reasons: features.artifactFlags.isEmpty ? [proposal.reason] : features.artifactFlags,
                candidate: proposal.experimentalCandidate))
        }
        // Content check happens after the same read that generated the windows.
        // Renaming a training recording cannot turn it into a held-out recording.
        let contentDigest = try fingerprint.finalize()
        guard !profile.trainingRecordingHashes.values.contains(contentDigest) else { throw Failure.trainingRecording }
        return EEGReplayInferenceReport(profileID: profile.id, recordingSHA256: digest, eegContentSHA256: contentDigest,
            participantID: participantID, sessionID: sessionID, windows: rows)
    }
}
