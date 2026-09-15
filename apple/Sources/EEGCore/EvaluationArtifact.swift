import Foundation
import CryptoKit

/// A reproducible evaluation receipt. Source recordings and the referenced profile
/// are still required for replay; this artifact is not a raw-data archive.
public struct EEGEvaluationArtifact: Sendable {
    public let report: EEGLabeledEvaluation
    public let data: Data
    public let sessionResampling: [String: EEGSessionResampling.Result]?
    public static func run(manifest: Data, store: EEGRecordingStore, profile: EEGMentalProfile,
                           controlsOnly: Bool = false, resampling: EEGSessionResampling.Options? = nil) throws -> EEGEvaluationArtifact {
        try resampling?.validate()
        let dataset = try EEGTrainingDataset.load(manifest, store: store, settings: profile.settings)
        let report = try EEGLabeledEvaluation.run(profile: profile, dataset: dataset, controlsOnly: controlsOnly)
        return try make(report: report, dataset: dataset, manifest: manifest, profile: profile, resampling: resampling)
    }
    // Internal so production callers cannot attach an unrelated manifest to results.
    static func make(report: EEGLabeledEvaluation, dataset: EEGTrainingDataset, manifest: Data,
                     profile: EEGMentalProfile, resampling: EEGSessionResampling.Options? = nil) throws -> EEGEvaluationArtifact {
        try resampling?.validate()
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
             "false_negative": metric.falseNegative, "actual_windows": metric.actualWindows,
             "rejected_windows": metric.rejectedWindows, "rejection_fraction": nullable(metric.rejectionFraction), "precision": nullable(metric.precision), "recall": nullable(metric.recall)]
        }
        let metrics = report.metrics.mapValues(metricObject)
        let sessionMetrics = report.sessionMetrics.mapValues { $0.mapValues(metricObject) }
        func trialMetricObject(_ metric: EEGLabeledEvaluation.TrialMetric) -> [String: Any] {
            ["declared_trials": metric.declaredTrials, "scored_trials": metric.scoredTrials,
             "observed_trials": metric.observedTrials, "unavailable_trials": metric.unavailableTrials,
             "no_candidate_observed_trials": metric.noCandidateObservedTrials,
             "trials_without_eligible_exposure": metric.trialsWithoutEligibleExposure,
             "declared_seconds": metric.declaredSeconds, "eligible_seconds": metric.eligibleSeconds,
             "observation_fraction": nullable(metric.observationFraction), "eligible_fraction": nullable(metric.eligibleFraction)]
        }
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
             "eligible_seconds": trial.eligibleSeconds, "eligible_fraction": trial.eligibleFraction,
             "contained_candidate_windows": trial.containedCandidateWindows,
             "contained_target_windows": trial.containedTargetWindows,
             "scored_target_detected": nullable(trial.scoredTargetDetected),
             "scored_neutral_false_positive": nullable(trial.scoredNeutralFalsePositive),
             "first_cue_associated_candidate_latency_seconds": nullable(trial.firstCueAssociatedCandidateLatency),
             "cued_target_detected": nullable(trial.cuedTargetDetected)]
        }
        let sources: [[String: Any]] = dataset.sessions.map { session in
            ["session_id": session.id, "split": session.split, "file_sha256": session.fileSHA256,
             "eeg_content_sha256": session.eegSHA256, "usable_windows": session.usableWindows,
             "rejected_windows": session.rejectedWindows]
        }
        var sessionResampling: [String: EEGSessionResampling.Result]?
        if let resampling {
            let summaries = report.sessionTrialMetrics
            sessionResampling = try Dictionary(uniqueKeysWithValues: report.metrics.keys.sorted().map { label in
                let rows = summaries.compactMapValues { $0[label] }
                return (label, try EEGSessionResampling.run(rows, options: resampling))
            })
        }
        let object: [String: Any] = [
            "schema": "eeg.native-evaluation.v1", "algorithm_version": "native-labeled-evaluation-6",
            "profile_id": profile.id, "parent_profile_id": nullable(profile.parentProfileID), "feature_config_id": EEGMentalFeatures.configurationID,
            "processing_settings": try JSONSerialization.jsonObject(with: profile.settings.jsonData()),
            "participant_id": dataset.participantID, "controls_only": report.controlsOnly,
            "system_control_enabled": false, "hardware_validated": false,
            "manifest_base64": manifest.base64EncodedString(),
            "manifest_sha256": SHA256.hash(data: manifest).map { String(format: "%02x", $0) }.joined(),
            "session_resampling": try sessionResampling.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) } ?? NSNull(),
            "trial_metrics": report.trialMetrics.mapValues(trialMetricObject),
            "session_trial_metrics": report.sessionTrialMetrics.mapValues { $0.mapValues(trialMetricObject) },
            "sources": sources, "predictions": predictions, "metrics": metrics, "session_metrics": sessionMetrics,
            "control_conditions_without_eligible_exposure": report.controlConditionsWithoutEligibleExposure,
            "trials": trials, "conditions": conditions, "session_conditions": sessionConditions, "rejection_fraction": report.rejectionFraction,
            "definitions": [
                "time_axis": "recorded receipt-time seconds; window end is the last sample receipt",
                "prediction": "experimental candidate or explicit neutral; null is rejection, not neutral",
                "dataset_excerpt_check": "canonical-counter-adc-blocks-v1: scans every sample offset against 256-sample blocks of earlier manifest sessions; exact bytes confirm rolling-hash candidates; covers samples emitted by analysisWindows; no independence proof",
                "class_rejection": "null predictions divided by windows of the actual class; includes unarmed and unusable windows; null rate when the class is absent",
                "scored_trial": "candidate persistence evidence must start within the scored interval and at or after the recorded cue; task success requires the target label, neutral false positive accepts any task candidate; missing cue yields null; carry-ins are not credited",
                "session_resampling": "optional exploratory whole-session pair resampling; not validated confidence coverage; assumes independent exchangeable sessions; few sessions, selection and missing exposure limit interpretation; never a qualification gate",
                "trial_metrics": "cued task target observations or cued neutral false positives; one observation per declared trial; missing cues counted unavailable; zero eligible exposure retained; controls reported separately; no confidence or independence claim",
                "trial_eligible_fraction": "armed usable window duration divided by the declared scored interval; includes gaps in denominator; not confidence or physiological validity",
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
                "Profile hashes detect complete training-recording reuse; excerpt checks compare only source sessions present in this manifest. Short or transformed excerpts and absent historical training sources are not excluded.",
                "Parent lineage does not audit historical model-selection or evaluation reuse."]
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
        return EEGEvaluationArtifact(report: report, data: data, sessionResampling: sessionResampling)
    }
}
