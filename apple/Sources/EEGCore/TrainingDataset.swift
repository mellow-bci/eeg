import Foundation

public struct EEGTrainingDataset: Sendable {
    public struct SessionSummary: Sendable {
        public let id: String
        public let split: String
        public let fileSHA256: String
        public let eegSHA256: String
        public let usableWindows: Int
        public let rejectedWindows: Int
    }
    public let participantID: String
    public let records: [EEGTrainingRecord]
    public let sessions: [SessionSummary]

    public enum Failure: Error { case invalidManifest, invalidTrial, duplicateSession, duplicateRecording, trialWithoutWindows }
    private struct Manifest: Decodable {
        let schema: String, participant_id: String
        let sessions: [Session]
    }
    private struct Session: Decodable {
        let id: String, split: String, recording: String
        let independent_session: Bool
        let trials: [Trial]
    }
    private struct Trial: Decodable {
        let id: String, label: String
        let start: Double, end: Double
        let accepted: Bool, label_verified: Bool
        let condition: String?
        let shadow_enabled: Bool?
        let cue_completed_at: Double?
    }

    /// Native eeg.dataset.v1 adapter. Recording names resolve only inside the local
    /// store. All sessions are validated; only training windows enter the trainer.
    public static func load(_ data: Data, store: EEGRecordingStore,
                            settings: ProcessingSettings = ProcessingSettings()) throws -> EEGTrainingDataset {
        try settings.validate()
        guard data.count <= 8 * 1024 * 1024 else { throw Failure.invalidManifest }
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.schema == "eeg.dataset.v1", !manifest.participant_id.isEmpty, !manifest.sessions.isEmpty else { throw Failure.invalidManifest }
        var seenSessions = Set<String>(), seenContent = Set<String>()
        var training = [EEGTrainingRecord](), summaries = [SessionSummary]()
        for session in manifest.sessions {
            guard !session.id.isEmpty, seenSessions.insert(session.id).inserted else { throw Failure.duplicateSession }
            guard session.independent_session, ["train", "evaluation"].contains(session.split),
                  !session.recording.isEmpty, session.recording == URL(fileURLWithPath: session.recording).lastPathComponent,
                  !session.trials.isEmpty else { throw Failure.invalidManifest }
            var trialIDs = Set<String>(), intervals = [(Double, Double)]()
            for trial in session.trials {
                let condition = trial.condition ?? (trial.label == "neutral" ? "cued_neutral" : "cued_task")
                guard !trial.id.isEmpty, trialIDs.insert(trial.id).inserted, !trial.label.isEmpty, trial.label.count <= 80,
                      trial.accepted, trial.label_verified, trial.start.isFinite, trial.end.isFinite, trial.end > trial.start,
                      !intervals.contains(where: { trial.start < $0.1 && trial.end > $0.0 }),
                      ["cued_task", "cued_neutral", "ordinary_activity", "blink_control", "jaw_control", "head_movement_control"].contains(condition),
                      (condition == "cued_task") == (trial.label != "neutral"),
                      session.split != "train" || (["cued_task", "cued_neutral"].contains(condition) && trial.shadow_enabled != false) else { throw Failure.invalidTrial }
                if let cue = trial.cue_completed_at { guard cue.isFinite, cue <= trial.end else { throw Failure.invalidTrial } }
                intervals.append((trial.start, trial.end))
            }
            var fingerprint = EEGRecordingFingerprint(), matched = Set<String>()
            var usable = 0, rejected = 0
            var pending = [(Int, String, [Double])]()
            let fileHash = try store.analysisWindows(recording: store.directory.appendingPathComponent(session.recording)) { window in
                for sample in window.samples { try fingerprint.append(sample) }
                guard let first = window.samples.first, let last = window.samples.last,
                      let trial = session.trials.first(where: { $0.start <= first.receivedAt && last.receivedAt <= $0.end }) else { return }
                matched.insert(trial.id)
                guard window.valid, let features = try? EEGMentalFeatures.extract(samples: window.samples), features.usable else { rejected += 1; return }
                usable += 1
                if session.split == "train" {
                    if let limit = settings.maxTrainingWindows, training.count + pending.count >= limit { throw EEGTrainingData.Failure.resourceLimit }
                    pending.append((window.ordinal, trial.label, features.values))
                }
            }
            guard matched == trialIDs else { throw Failure.trialWithoutWindows }
            let eegHash = try fingerprint.finalize()
            guard seenContent.insert(eegHash).inserted else { throw Failure.duplicateRecording }
            training += pending.map { ordinal, label, values in
                EEGTrainingRecord(accepted: true, label_verified: true, artifact_flags: [], usable: true,
                    feature_config_id: EEGMentalFeatures.configurationID, participant_id: manifest.participant_id,
                    window_id: "\(fileHash):\(ordinal)", session_id: session.id, label: label,
                    recording_content_sha256: eegHash, values: values)
            }
            summaries.append(SessionSummary(id: session.id, split: session.split, fileSHA256: fileHash,
                eegSHA256: eegHash, usableWindows: usable, rejectedWindows: rejected))
        }
        return EEGTrainingDataset(participantID: manifest.participant_id, records: training, sessions: summaries)
    }
}
