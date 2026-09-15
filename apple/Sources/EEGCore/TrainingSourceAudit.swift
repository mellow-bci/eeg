import Foundation

/// Coverage of the saved profile's source recordings in the current dataset.
/// Matching content hashes do not prove authorship or acquisition independence.
public struct EEGTrainingSourceAudit: Codable, Sendable, Equatable {
    public struct Match: Codable, Sendable, Equatable {
        public let trainingSessionID: String
        public let eegSHA256: String
        public let manifestSessionIDs: [String]
        enum CodingKeys: String, CodingKey {
            case trainingSessionID = "training_session_id", eegSHA256 = "eeg_sha256", manifestSessionIDs = "manifest_session_ids"
        }
    }
    public let schema: String
    public let matches: [Match]
    public let missingTrainingSessions: [String]
    enum CodingKeys: String, CodingKey {
        case schema, matches, missingTrainingSessions = "missing_training_sessions"
    }
    public var status: String {
        missingTrainingSessions.isEmpty ? "all_training_sources_present" : "training_sources_missing"
    }
    static func run(profile: EEGMentalProfile, sessions: [EEGTrainingDataset.SessionSummary]) throws -> Self {
        // A familiar ID with altered samples must not stand in for the saved source.
        for source in sessions where source.split == "train" {
            if let expected = profile.trainingRecordingHashes[source.id], expected != source.eegSHA256 {
                throw EEGLabeledEvaluation.Failure.trainingSourceMismatch
            }
        }
        var matches = [Match](), missing = [String]()
        for id in profile.trainingSessions.sorted() {
            let expected = profile.trainingRecordingHashes[id]!
            let present = sessions.filter { $0.split == "train" && $0.eegSHA256 == expected }.map(\.id).sorted()
            if present.isEmpty { missing.append(id) }
            else { matches.append(Match(trainingSessionID: id, eegSHA256: expected, manifestSessionIDs: present)) }
        }
        return Self(schema: "eeg.training-source-audit.v1", matches: matches, missingTrainingSessions: missing)
    }
}
