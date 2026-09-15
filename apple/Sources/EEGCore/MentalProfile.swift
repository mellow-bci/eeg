import Foundation

/// Existing eeg.mental-profile.v2 artifact, produced by the independent trainer.
/// Only load(data:) exposes a validated instance. No experimental file can enable actions.
public struct EEGMentalProfile: Sendable {
    public let id: String
    public let parentProfileID: String?
    public let participantID: String
    public let settings: ProcessingSettings
    public let parameters: EEGMentalScoringParameters
    public let trainingSessions: [String]
    public let trainingRecordingHashes: [String: String]
    private init(id: String, parentProfileID: String?, participantID: String, settings: ProcessingSettings,
                 parameters: EEGMentalScoringParameters, trainingSessions: [String], trainingRecordingHashes: [String: String]) {
        self.parentProfileID = parentProfileID
        self.id = id; self.participantID = participantID; self.settings = settings
        self.parameters = parameters; self.trainingSessions = trainingSessions; self.trainingRecordingHashes = trainingRecordingHashes
    }
    public enum Failure: Error { case unsupported, integrity, provenance, design }
    public static func load(data: Data) throws -> EEGMentalProfile {
        let checksum = try ProfileCanonicalJSON.digest(data)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["profile_id"] as? String, checksum == id else { throw Failure.integrity }
        let decoded = try JSONDecoder().decode(Fields.self, from: data)
        guard decoded.schema == "eeg.mental-profile.v2",
              decoded.feature_config_id == EEGMentalFeatures.configurationID,
              decoded.validation_status == "experimental_unvalidated", !decoded.system_control_enabled else { throw Failure.unsupported }
        let sessions = decoded.training_sessions, ids = decoded.training_window_ids
        func hash(_ s: String) -> Bool { s.count == 64 && s.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
        if let parent = decoded.parent_profile_id { guard hash(parent), parent != id else { throw Failure.provenance } }
        guard !decoded.participant_id.isEmpty, sessions.count >= 2, Set(sessions).count == sessions.count,
              sessions.allSatisfy({ !$0.isEmpty }), Set(sessions) == Set(decoded.training_recording_hashes.keys),
              Set(decoded.training_recording_hashes.values).count == sessions.count,
              decoded.training_recording_hashes.values.allSatisfy(hash), !ids.isEmpty,
              ids.allSatisfy({ !$0.isEmpty }), Set(ids).count == ids.count,
              hash(decoded.training_records_sha256) else { throw Failure.provenance }
        guard let settingsObject = object["processing_settings"] as? [String: Any],
              Set(settingsObject.keys) == Set(["schema", "max_training_windows", "selected_features", "pca_components", "variance_floor", "score_threshold", "margin_threshold", "persistence_windows"]) else { throw Failure.design }
        let settings = decoded.processing_settings
        let parameters = try JSONDecoder().decode(EEGMentalScoringParameters.self, from: data)
        guard parameters.selected.count == settings.selectedFeatures,
              parameters.components.count == min(settings.pcaComponents, ids.count - parameters.classes.count, parameters.selected.count),
              let design = object["design"] as? [String: Any],
              NSDictionary(dictionary: design).isEqual(to: [
                "origin":"independent_design_not_recovered_cortex",
                "feature_selection":"training-only between/within variance ratio",
                "selected_features":settings.selectedFeatures, "pca_components":settings.pcaComponents,
                "gaussian":"diagonal_regularized", "variance_floor":settings.varianceFloor,
                "class_prior":"equal", "score_threshold":settings.scoreThreshold,
                "margin_threshold":settings.marginThreshold, "persistence_windows":settings.persistenceWindows,
                "parameters_physiologically_validated":false]) else { throw Failure.design }
        _ = try EEGMentalScoring.score(values: parameters.center, parameters: parameters)
        // Consistency with the independent trainer's declared PCA/Gaussian recipe.
        // The checksum alone cannot establish these invariants or training provenance.
        for (i, row) in parameters.components.enumerated() {
            for j in 0...i {
                let dot = zip(row, parameters.components[j]).reduce(0.0) { $0 + $1.0 * $1.1 }
                guard dot.isFinite, abs(dot - (i == j ? 1 : 0)) <= 1e-6 else { throw Failure.design }
            }
        }
        guard parameters.gaussians.allSatisfy({ gaussian in
            gaussian.variance.allSatisfy { $0 >= settings.varianceFloor } &&
            gaussian.distance_limit >= 4 * Double(parameters.components.count)
        }) else { throw Failure.design }
        return EEGMentalProfile(id: id, parentProfileID: decoded.parent_profile_id, participantID: decoded.participant_id, settings: settings,
                                parameters: parameters, trainingSessions: sessions, trainingRecordingHashes: decoded.training_recording_hashes)
    }
    public func makeDetector() throws -> EEGExperimentalDetector {
        try EEGExperimentalDetector(parameters: parameters, settings: settings, participantID: participantID, profileID: id)
    }
    private struct Fields: Decodable {
        let schema: String, profile_id: String, feature_config_id: String, participant_id: String
        let parent_profile_id: String?
        let validation_status: String, system_control_enabled: Bool
        let processing_settings: ProcessingSettings
        let training_sessions: [String], training_window_ids: [String]
        let training_recording_hashes: [String: String], training_records_sha256: String
    }
}
