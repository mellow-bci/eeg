import Foundation

// Presentation only: these descriptions do not relax validation or supply labels.
extension EEGTrainingData.Failure: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidRecords: return "No valid training records for this participant. Check the participant and accepted training trials."
        case .unverifiedLabels: return "Training labels have not been accepted and verified. Review the trials; exclude uncertain attempts."
        case .invalidFeatures: return "Training features are unusable or incompatible. Re-extract from the original recordings using the current processing configuration."
        case .duplicateWindows: return "A training window appears more than once. Remove duplicate dataset entries."
        case .sessionProvenance: return "Training requires at least two distinct recording sessions with consistent content hashes. Copies of a recording cannot count as independent sessions."
        case .insufficientClasses: return "Training requires neutral and at least one task class. Record and review both conditions."
        case .insufficientClassSessions: return "Each class needs at least 20 usable windows across at least two independent sessions. Collect additional trials instead of duplicating windows."
        case .resourceLimit: return "The dataset exceeds the saved training-window limit. Review Processing settings or select a smaller training dataset."
        case .numericalFailure: return "Feature preparation produced invalid numerical values. Keep the original recordings and inspect the input features before retrying."
        }
    }
}
extension EEGTrainingDataset.Failure: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidManifest: return "The dataset manifest is invalid or its source hash does not match. Use an exported eeg.dataset.v1 manifest and its unchanged local recordings."
        case .invalidTrial: return "A trial has invalid labels, timing, condition or acceptance evidence. Review the source trials and rebuild the manifest."
        case .duplicateSession: return "Session identifiers must be nonempty and unique within the dataset."
        case .duplicateRecording: return "The dataset reuses EEG recording content. Use independently collected sessions for training and evaluation."
        case .reusedRecordingExcerpt: return "Different sessions contain an identical EEG sample block. Do not split or rename reused recordings to claim independent training or evaluation. Inspect the sources; a match does not establish how it arose."
        case .trialWithoutWindows: return "A labeled interval contains no complete analysis windows. Check recording coverage and trial timing."
        }
    }
}
extension EEGLabeledEvaluation.Failure: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noEvaluation: return "The dataset has no evaluation windows. Add held-out recording sessions."
        case .participantMismatch: return "The dataset participant does not match the saved profile. Select the matching profile."
        case .trainingSourceMismatch: return "A manifest training session has different EEG content from the saved profile source. Restore the original source or use the correct profile; a matching session name is not sufficient."
        case .trainingOverlap: return "Evaluation overlaps the profile's training sessions or recording content. Use new held-out recordings."
        case .insufficientClassWindows: return "Full evaluation needs at least 10 windows per profile class. Add held-out trials; use controls-only mode only for a neutral control dataset."
        case .invalidLabels: return "Evaluation labels do not match the profile or selected evaluation scope. Check task labels and control conditions."
        case .invalidTiming: return "Evaluation windows have invalid or conflicting timing. Rebuild the dataset from the original recording evidence."
        }
    }
}
