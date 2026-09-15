import Foundation
import CryptoKit

/// A reproducible evaluation receipt. Source recordings and the referenced profile
/// are still required for replay; this artifact is not a raw-data archive.
public struct EEGEvaluationArtifact: Sendable {
    public let report: EEGLabeledEvaluation
    public let data: Data
    public static func run(manifest: Data, store: EEGRecordingStore, profile: EEGMentalProfile,
                           controlsOnly: Bool = false) throws -> EEGEvaluationArtifact {
        let dataset = try EEGTrainingDataset.load(manifest, store: store, settings: profile.settings)
        let report = try EEGLabeledEvaluation.run(profile: profile, dataset: dataset, controlsOnly: controlsOnly)
        return try make(report: report, dataset: dataset, manifest: manifest, profile: profile)
    }
    // Internal so production callers cannot attach an unrelated manifest to results.
    static func make(report: EEGLabeledEvaluation, dataset: EEGTrainingDataset, manifest: Data,
                     profile: EEGMentalProfile) throws -> EEGEvaluationArtifact {
        func nullable<T>(_ value: T?) -> Any { value.map { $0 as Any } ?? NSNull() }
        let predictions: [[String: Any]] = zip(report.predictions, dataset.evaluation).map { prediction, row in
            ["window_id": prediction.windowID, "session_id": prediction.sessionID,
             "trial_id": prediction.trialID, "actual_label": prediction.actual,
             "predicted_label": nullable(prediction.predictedLabel), "reason": prediction.reason,
             "input_usable": prediction.inputUsable, "start_seconds": row.input.start,
             "end_seconds": row.input.end, "continuity_id": row.input.continuity_id,
             "artifact_flags": row.input.artifact_flags, "shadow_enabled": row.shadowEnabled,
             "condition": row.condition]
        }
        func metricObject(_ metric: EEGLabeledEvaluation.Metric) -> [String: Any] {
            ["true_positive": metric.truePositive, "false_positive": metric.falsePositive,
             "false_negative": metric.falseNegative, "precision": nullable(metric.precision), "recall": nullable(metric.recall)]
        }
        let metrics = report.metrics.mapValues(metricObject)
        let sessionMetrics = report.sessionMetrics.mapValues { $0.mapValues(metricObject) }
        func exposureObject(_ exposure: EEGConditionExposure) -> [String: Any] {
            ["eligible_seconds": exposure.eligibleSeconds, "unarmed_seconds": exposure.unarmedSeconds,
             "rejected_seconds": exposure.rejectedSeconds, "candidate_windows": exposure.candidateWindows,
             "episode_onsets": exposure.episodeOnsets, "carry_in_candidates": exposure.carryInCandidates,
             "empirical_episodes_per_hour": nullable(exposure.episodeOnsetsPerHour),
             "poisson_upper_95_per_hour": nullable(exposure.poissonUpper95PerHour)]
        }
        let conditions = report.conditions.mapValues(exposureObject)
        let sessionConditions = report.sessionConditions.mapValues { $0.mapValues(exposureObject) }
        let trials: [[String: Any]] = report.trials.map { trial in
            ["session_id": trial.sessionID, "trial_id": trial.trialID, "label": trial.label,
             "condition": trial.condition, "start_seconds": trial.start, "end_seconds": trial.end,
             "cue_completed_at_seconds": nullable(trial.cueCompletedAt), "covered_seconds": trial.coveredSeconds,
             "unobserved_seconds": trial.unobservedSeconds,
             "first_cue_associated_candidate_latency_seconds": nullable(trial.firstCueAssociatedCandidateLatency),
             "cued_target_detected": nullable(trial.cuedTargetDetected)]
        }
        let sources: [[String: Any]] = dataset.sessions.map { session in
            ["session_id": session.id, "split": session.split, "file_sha256": session.fileSHA256,
             "eeg_content_sha256": session.eegSHA256, "usable_windows": session.usableWindows,
             "rejected_windows": session.rejectedWindows]
        }
        let object: [String: Any] = [
            "schema": "eeg.native-evaluation.v1", "algorithm_version": "native-labeled-evaluation-2",
            "profile_id": profile.id, "parent_profile_id": nullable(profile.parentProfileID), "feature_config_id": EEGMentalFeatures.configurationID,
            "processing_settings": try JSONSerialization.jsonObject(with: profile.settings.jsonData()),
            "participant_id": dataset.participantID, "controls_only": report.controlsOnly,
            "system_control_enabled": false, "hardware_validated": false,
            "manifest_base64": manifest.base64EncodedString(),
            "manifest_sha256": SHA256.hash(data: manifest).map { String(format: "%02x", $0) }.joined(),
            "sources": sources, "predictions": predictions, "metrics": metrics, "session_metrics": sessionMetrics,
            "control_conditions_without_eligible_exposure": report.controlConditionsWithoutEligibleExposure,
            "trials": trials, "conditions": conditions, "session_conditions": sessionConditions, "rejection_fraction": report.rejectionFraction,
            "definitions": [
                "time_axis": "recorded receipt-time seconds; window end is the last sample receipt",
                "prediction": "experimental candidate or explicit neutral; null is rejection, not neutral",
                "latency": "recorded cue completion to candidate input availability, not mental onset or live response",
                "poisson_bound": "one-sided 95% upper bound; assumes constant independent event rate; unavailable for carry-ins or zero eligible exposure",
                "control_coverage": "lists required artifact-control conditions with zero eligible exposure; an empty list does not establish adequate duration or qualification",
                "session_conditions": "exposure and onset counts by session and condition; pooled rates can hide between-session variability",
                "labels": "participant/operator declarations, not independent physiological ground truth",
                "reproduction": "requires this manifest, the referenced original recordings and matching profile; verify both source digests"
            ],
            "limitations": ["Correlated windows are not independent trials.",
                "Control-only results do not measure task recall.",
                "No physiological accuracy or safe system control is established.",
                "Hashes detect changes; they do not authenticate authorship.",
                "Source files are read as streams, not locked immutable snapshots.",
                "Training overlap checks cover this profile; parent lineage does not audit historical model-selection or evaluation reuse."]
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
        return EEGEvaluationArtifact(report: report, data: data)
    }
}
