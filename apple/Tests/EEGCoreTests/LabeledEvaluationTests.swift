import Foundation
import XCTest
@testable import EEGCore

final class LabeledEvaluationTests: XCTestCase {
    func testCancelledReceiptCannotPublishAndIndependentRetryMatches() async throws {
        let (profile, dataset, _) = try fixture()
        let report = try EEGLabeledEvaluation.run(profile: profile, dataset: dataset)
        let manifest = Data("synthetic cancellation fixture".utf8)
        let baseline = try EEGEvaluationArtifact.make(report: report, dataset: dataset, manifest: manifest, profile: profile)
        let cancelled = Task.detached { () throws -> EEGEvaluationArtifact in
            // Cancel this worker deterministically; no sleeps or scheduling race.
            withUnsafeCurrentTask { $0?.cancel() }
            return try EEGEvaluationArtifact.make(report: report, dataset: dataset, manifest: manifest, profile: profile)
        }
        do {
            _ = try await cancelled.value
            XCTFail("Cancelled worker published an evaluation receipt")
        } catch is CancellationError {
            // Cancellation must remain an error, not an unavailable/success receipt.
        } catch { XCTFail("Unexpected error: \(error)") }
        let retry = try EEGEvaluationArtifact.make(report: report, dataset: dataset, manifest: manifest, profile: profile)
        XCTAssertEqual(retry.data, baseline.data)
        XCTAssertFalse(retry.report.systemControlEnabled)
    }
    func testConfigurableMinimumRejectsInsufficientDataWithoutChangingInference() throws {
        let (profile, dataset, _) = try fixture()
        let defaultReport = try EEGLabeledEvaluation.run(profile: profile, dataset: dataset)
        let relaxed = try EEGLabeledEvaluation.run(profile: profile, dataset: dataset, minimumWindowsPerClass: 1)
        XCTAssertEqual(defaultReport.minimumWindowsPerClass, 10)
        XCTAssertEqual(relaxed.predictions.map(\.predictedLabel), defaultReport.predictions.map(\.predictedLabel))
        XCTAssertThrowsError(try EEGLabeledEvaluation.run(profile: profile, dataset: dataset, minimumWindowsPerClass: 11)) {
            guard case EEGLabeledEvaluation.Failure.insufficientClassWindows = $0 else { return XCTFail("Unexpected error: \($0)") }
        }
        for invalid in [0, -1] {
            XCTAssertThrowsError(try EEGLabeledEvaluation.run(profile: profile, dataset: dataset, minimumWindowsPerClass: invalid)) {
                guard case EEGLabeledEvaluation.Failure.invalidMinimumWindows = $0 else { return XCTFail("Unexpected error: \($0)") }
            }
        }
        let receipt = try EEGEvaluationArtifact.make(report: relaxed, dataset: dataset, manifest: Data("fixture".utf8), profile: profile)
        let json = try JSONSerialization.jsonObject(with: receipt.data) as! [String: Any]
        XCTAssertEqual(json["minimum_windows_per_class"] as? Int, 1)
        let neutral = EEGTrainingDataset(evaluation: dataset.evaluation.filter { $0.label == "neutral" },
            participantID: dataset.participantID, records: [], sessions: dataset.sessions)
        let controls = try EEGLabeledEvaluation.run(profile: profile, dataset: neutral, controlsOnly: true, minimumWindowsPerClass: 1000)
        XCTAssertEqual(controls.minimumWindowsPerClass, 1000)
        XCTAssertFalse(controls.predictions.isEmpty)
    }
    func testMulticlassConfusionConservesWindowsAndSeparatesRejection() {
        let pairs: [(String, String?)] = [("left", "right"), ("left", nil), ("left", "left"),
            ("right", "neutral"), ("neutral", "left"), ("rejected", "rejected")]
        let predictions = pairs.enumerated().map { index, pair in
            EEGLabeledEvaluation.Prediction(windowID: String(index), sessionID: index % 2 == 0 ? "a" : "b", trialID: "t",
                actual: pair.0, predictedLabel: pair.1, reason: "fixture", inputUsable: pair.1 != nil)
        }
        let classes = ["neutral", "left", "right", "rejected", "absent"]
        let rows = EEGLabeledEvaluation.confusion(predictions, classes: classes)
        XCTAssertEqual(rows["left"]?.predictedCounts["right"], 1)
        XCTAssertEqual(rows["left"]?.rejectedWindows, 1)
        XCTAssertEqual(rows["left"]?.actualWindows, 3)
        XCTAssertEqual(rows["rejected"]?.predictedCounts["rejected"], 1)
        XCTAssertEqual(rows["rejected"]?.rejectedWindows, 0)
        XCTAssertEqual(rows["absent"]?.actualWindows, 0)
        XCTAssertEqual(rows.values.reduce(0) { $0 + $1.actualWindows }, predictions.count)
        let metrics = EEGLabeledEvaluation.summarize(predictions, classes: classes)
        for label in classes {
            XCTAssertEqual(rows[label]?.predictedCounts[label], metrics[label]?.truePositive)
            XCTAssertEqual(rows[label]?.actualWindows, metrics[label]?.actualWindows)
            XCTAssertEqual(rows[label]?.rejectedWindows, metrics[label]?.rejectedWindows)
        }
        XCTAssertEqual(EEGLabeledEvaluation.confusion(Array(predictions.reversed()), classes: classes), rows)
        let report = EEGLabeledEvaluation(minimumWindowsPerClass: 10, controlsOnly: false, profileID: "fixture", predictions: predictions,
            metrics: metrics, trials: [], conditions: [:], sessionConditions: [:])
        XCTAssertEqual(Set(report.sessionConfusion.keys), Set(["a", "b"]))
        XCTAssertEqual(report.sessionConfusion["a"]?["left"]?.rejectedWindows, 0)
        XCTAssertEqual(report.sessionConfusion["b"]?["left"]?.rejectedWindows, 1)
        for actual in classes {
            for predicted in classes {
                XCTAssertEqual(report.sessionConfusion.values.reduce(0) { $0 + $1[actual]!.predictedCounts[predicted]! }, rows[actual]!.predictedCounts[predicted])
            }
        }
    }
    func testClassRejectionDistinguishesWrongLabelNeutralAndMissingClass() throws {
        let pairs:[(String,String?)] = [("task",nil),("task","neutral"),("task","task"),("neutral","neutral")]
        let predictions = pairs.enumerated().map { index,pair in
            EEGLabeledEvaluation.Prediction(windowID:String(index),sessionID:"synthetic",trialID:"trial",
                actual:pair.0,predictedLabel:pair.1,reason:"test",inputUsable:true)
        }
        let metrics = EEGLabeledEvaluation.summarize(predictions,classes:["neutral","task","absent"])
        let task = try XCTUnwrap(metrics["task"])
        XCTAssertEqual(task.actualWindows,3)
        XCTAssertEqual(task.falseNegative,2)
        XCTAssertEqual(task.rejectedWindows,1)
        XCTAssertEqual(task.rejectionFraction,1.0/3.0)
        XCTAssertEqual(metrics["neutral"]?.rejectedWindows,0)
        XCTAssertEqual(metrics["neutral"]?.rejectionFraction,0)
        XCTAssertEqual(metrics["absent"]?.actualWindows,0)
        XCTAssertNil(metrics["absent"]?.rejectionFraction)
    }
    func testAlwaysNeutralBaselineIncludesRejectedWindowsAndClassImbalance() {
        let rows: [EEGLabeledEvaluation.Prediction] = ["neutral", "neutral", "neutral", "task"].enumerated().map { i, label in
            .init(windowID: String(i), sessionID: "s", trialID: "t", actual: label,
                predictedLabel: nil, reason: "rejected", inputUsable: false)
        }
        let baseline = EEGLabeledEvaluation.summarize(EEGLabeledEvaluation.neutralBaseline(rows), classes: ["neutral", "task", "absent"])
        XCTAssertEqual(baseline["neutral"]?.truePositive, 3)
        XCTAssertEqual(baseline["neutral"]?.falsePositive, 1)
        XCTAssertEqual(baseline["neutral"]?.precision, 0.75)
        XCTAssertEqual(baseline["neutral"]?.recall, 1)
        XCTAssertEqual(baseline["task"]?.falseNegative, 1)
        XCTAssertEqual(baseline["task"]?.recall, 0)
        XCTAssertNil(baseline["task"]?.precision)
        XCTAssertNil(baseline["absent"]?.recall)
        XCTAssertTrue(baseline.values.allSatisfy { $0.rejectedWindows == 0 })
        XCTAssertTrue(rows.allSatisfy { $0.predictedLabel == nil })
    }
    private func file(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("Fixtures/spectrum/" + name))
    }
    private func fixture(cueKnown: Bool = false) throws -> (EEGMentalProfile, EEGTrainingDataset, [String: Any]) {
        let profile = try EEGMentalProfile.load(data: file("mental-profile.json"))
        let object = try JSONSerialization.jsonObject(with: file("mental-evaluation.json")) as! [String: Any]
        let rows = object["records"] as! [[String: Any]]
        let windows = try rows.map { row -> EEGTrainingDataset.EvaluationWindow in
            let input = try JSONDecoder().decode(EEGInferenceWindow.self, from: JSONSerialization.data(withJSONObject: row))
            return .init(input: input, label: row["label"] as! String, trialID: row["trial_id"] as! String,
                condition: row["condition"] as! String, shadowEnabled: row["shadow_enabled"] as! Bool,
                trialStart: row["trial_start"] as! Double, trialEnd: row["trial_end"] as! Double, cueCompletedAt: cueKnown ? 0 : nil)
        }
        let summary = EEGTrainingDataset.SessionSummary(id: "evaluation", split: "evaluation", fileSHA256: "unused",
            eegSHA256: rows[0]["recording_content_sha256"] as! String, usableWindows: 19, rejectedWindows: 1)
        return (profile, EEGTrainingDataset(evaluation: windows, participantID: profile.participantID, records: [], sessions: [summary]), object["expected"] as! [String: Any])
    }
    func testTrialBaselineZeroRequiresAvailableCueEvidence() throws {
        let (profile, dataset, _) = try fixture(cueKnown: true)
        let report = try EEGLabeledEvaluation.run(profile: profile, dataset: dataset)
        let artifact = try EEGEvaluationArtifact.make(report: report, dataset: dataset, manifest: Data("fixture".utf8), profile: profile)
        let json = try JSONSerialization.jsonObject(with: artifact.data) as! [String: Any]
        let baseline = json["always_neutral_baseline"] as! [String: Any]
        let trials = baseline["trial_metrics"] as! [String: [String: Any]]
        XCTAssertFalse(trials.isEmpty)
        for value in trials.values {
            XCTAssertGreaterThan(value["scored_trials"] as! Int, 0)
            XCTAssertEqual(value["candidate_observation_fraction"] as? Double, 0)
            XCTAssertEqual(value["candidate_observed_trials"] as? Int, 0)
        }
    }
    func testPredictionsAndMetricsMatchPythonIncludingRejection() throws {
        let (profile, dataset, expected) = try fixture()
        let result = try EEGLabeledEvaluation.run(profile: profile, dataset: dataset)
        XCTAssertFalse(result.systemControlEnabled); XCTAssertFalse(result.hardwareValidated)
        XCTAssertEqual(result.rejectionFraction, expected["rejection_fraction"] as! Double, accuracy: 1e-12)
        for (row, oracle) in zip(result.predictions, expected["predictions"] as! [[String: Any]]) {
            let predicted = oracle["predicted"] as! String
            XCTAssertEqual(row.predictedLabel, predicted == "reject" ? nil : predicted)
        }
        let metrics = expected["metrics"] as! [String: [String: Any]]
        for (label, metric) in result.metrics {
            XCTAssertEqual(metric.truePositive, metrics[label]!["tp"] as! Int)
            XCTAssertEqual(metric.falsePositive, metrics[label]!["fp"] as! Int)
            XCTAssertEqual(metric.falseNegative, metrics[label]!["fn"] as! Int)
            XCTAssertEqual(metric.precision, metrics[label]!["precision"] as? Double)
            XCTAssertEqual(metric.recall, metrics[label]!["recall"] as? Double)
        }
        let exposure = (expected["shadow_measurements"] as! [String: Any])["conditions"] as! [String: [String: Any]]
        for (condition, metrics) in result.conditions {
            let oracle = exposure[condition]!
            XCTAssertEqual(metrics.eligibleSeconds, oracle["eligible_seconds"] as! Double, accuracy: 1e-12)
            XCTAssertEqual(metrics.unarmedSeconds, oracle["unarmed_seconds"] as! Double, accuracy: 1e-12)
            XCTAssertEqual(metrics.rejectedSeconds, oracle["signal_rejected_seconds"] as! Double, accuracy: 1e-12)
            XCTAssertEqual(metrics.episodeOnsets, oracle["episode_onsets"] as! Int)
            XCTAssertEqual(metrics.carryInCandidates, oracle["carry_in_candidates"] as! Int)
            XCTAssertEqual(metrics.episodeOnsetsPerHour, oracle["episode_onsets_per_hour"] as? Double)
            if let bound = oracle["one_sided_95_percent_poisson_upper_per_hour"] as? Double {
                XCTAssertEqual(try XCTUnwrap(metrics.poissonUpper95PerHour), bound, accuracy: max(1e-9, bound * 1e-10))
            } else { XCTAssertNil(metrics.poissonUpper95PerHour) }
        }
        let trials = (expected["shadow_measurements"] as! [String: Any])["trials"] as! [[String: Any]]
        for (trial, oracle) in zip(result.trials, trials) {
            XCTAssertEqual(trial.unobservedSeconds, oracle["unobserved_seconds"] as! Double, accuracy: 1e-12)
            XCTAssertEqual(trial.firstCueAssociatedCandidateLatency, oracle["first_cue_associated_candidate_latency_seconds"] as? Double)
            XCTAssertEqual(trial.cuedTargetDetected, oracle["cued_target_detected"] as? Bool)
        }
        XCTAssertNil(result.predictions[1].predictedLabel)
        XCTAssertNil(result.predictions[2].predictedLabel)
    }
    func testTrainingOverlapAndInsufficientEvaluationRejected() throws {
        let (profile, dataset, _) = try fixture()
        let overlap = EEGTrainingDataset.SessionSummary(id: "evaluation", split: "evaluation", fileSHA256: "unused",
            eegSHA256: profile.trainingRecordingHashes.values.first!, usableWindows: 20, rejectedWindows: 0)
        XCTAssertThrowsError(try EEGLabeledEvaluation.run(profile: profile,
            dataset: EEGTrainingDataset(evaluation: dataset.evaluation, participantID: profile.participantID, records: [], sessions: [overlap])))
        XCTAssertThrowsError(try EEGLabeledEvaluation.run(profile: profile,
            dataset: EEGTrainingDataset(evaluation: Array(dataset.evaluation.prefix(5)), participantID: profile.participantID, records: [], sessions: dataset.sessions)))
    }
    func testTrainingSourceCoverageAndContradictoryContent() throws {
        let (profile, dataset, _) = try fixture()
        let absent = try EEGTrainingSourceAudit.run(profile: profile, sessions: dataset.sessions)
        XCTAssertEqual(absent.status, "training_sources_missing")
        XCTAssertEqual(absent.missingTrainingSessions, profile.trainingSessions.sorted())
        let originals = profile.trainingSessions.map { id in
            EEGTrainingDataset.SessionSummary(id: id, split: "train", fileSHA256: "unused",
                eegSHA256: profile.trainingRecordingHashes[id]!, usableWindows: 20, rejectedWindows: 0)
        }
        let complete = try EEGTrainingSourceAudit.run(profile: profile, sessions: originals + dataset.sessions)
        XCTAssertEqual(complete.status, "all_training_sources_present")
        XCTAssertTrue(complete.missingTrainingSessions.isEmpty)
        XCTAssertEqual(complete.matches.map(\.trainingSessionID), profile.trainingSessions.sorted())
        let first = originals[0]
        let renamed = EEGTrainingDataset.SessionSummary(id: "renamed-source", split: "train", fileSHA256: "different",
            eegSHA256: first.eegSHA256, usableWindows: 20, rejectedWindows: 0)
        let partial = try EEGTrainingSourceAudit.run(profile: profile, sessions: [renamed])
        XCTAssertEqual(partial.matches.first?.manifestSessionIDs, ["renamed-source"])
        XCTAssertEqual(partial.missingTrainingSessions.count, profile.trainingSessions.count - 1)
        let changed = EEGTrainingDataset.SessionSummary(id: first.id, split: "train", fileSHA256: "unused",
            eegSHA256: String(repeating: "0", count: 64), usableWindows: 20, rejectedWindows: 0)
        let conflicting = EEGTrainingDataset(evaluation: dataset.evaluation, participantID: dataset.participantID,
            records: [], sessions: [changed] + dataset.sessions)
        XCTAssertThrowsError(try EEGLabeledEvaluation.run(profile: profile, dataset: conflicting)) { error in
            guard case EEGLabeledEvaluation.Failure.trainingSourceMismatch = error else { return XCTFail("Unexpected: \(error)") }
        }
        let report = try EEGLabeledEvaluation.run(profile: profile, dataset: dataset)
        let artifact = try EEGEvaluationArtifact.make(report: report, dataset: dataset, manifest: Data("fixture".utf8), profile: profile)
        let json = try JSONSerialization.jsonObject(with: artifact.data) as! [String: Any]
        let baseline = json["always_neutral_baseline"] as! [String: Any]
        let trials = baseline["trial_metrics"] as! [String: [String: Any]]
        for value in trials.values {
            XCTAssertEqual(value["candidate_observed_trials"] as? Int, 0)
            XCTAssertTrue(value["candidate_observation_fraction"] is NSNull)
        }
        let bySession = baseline["session_metrics"] as! [String: Any]
        XCTAssertEqual(Set(bySession.keys), Set(dataset.evaluation.map { $0.input.session_id }))
        XCTAssertEqual(artifact.report.alwaysNeutralMetrics["task"]?.recall, 0)
        let audit = json["training_source_audit"] as! [String: Any]
        XCTAssertEqual(audit["status"] as? String, "training_sources_missing")
        XCTAssertEqual(audit["missing_training_sessions"] as? [String], profile.trainingSessions.sorted())
        XCTAssertFalse(artifact.report.systemControlEnabled)
    }

    func testControlsOnlyCannotBeMistakenForTaskEvaluation() throws {
        let (profile, full, _) = try fixture()
        let controls = EEGTrainingDataset(evaluation: full.evaluation.filter { $0.label == "neutral" },
            participantID: profile.participantID, records: [], sessions: full.sessions)
        XCTAssertThrowsError(try EEGLabeledEvaluation.run(profile: profile, dataset: controls))
        let result = try EEGLabeledEvaluation.run(profile: profile, dataset: controls, controlsOnly: true)
        XCTAssertTrue(result.controlsOnly)
        XCTAssertEqual(result.predictions.count, 10)
        XCTAssertNil(result.metrics["task"]?.recall)
        XCTAssertThrowsError(try EEGLabeledEvaluation.run(profile: profile, dataset: full, controlsOnly: true))
    }

    func testReceiptIncludesValidatedParentReference() throws {
        let (_, dataset, _) = try fixture()
        var object = try JSONSerialization.jsonObject(with:file("mental-profile.json")) as! [String:Any]
        let parent = String(repeating:"a",count:64)
        object["parent_profile_id"] = parent
        object["profile_id"] = try ProfileCanonicalJSON.digest(PythonCompatibleJSON.encode(object))
        let profile = try EEGMentalProfile.load(data:PythonCompatibleJSON.encode(object))
        let report = try EEGLabeledEvaluation.run(profile:profile,dataset:dataset)
        let receipt = try EEGEvaluationArtifact.make(report:report,dataset:dataset,manifest:Data("fixture".utf8),profile:profile)
        let saved = try JSONSerialization.jsonObject(with:receipt.data) as! [String:Any]
        XCTAssertEqual(saved["parent_profile_id"] as? String,parent)
        XCTAssertEqual(saved["system_control_enabled"] as? Bool,false)
    }

    func testReceiptKeepsUnavailableValuesAndRejectionsExplicit() throws {
        let (profile, full, _) = try fixture()
        let dataset = EEGTrainingDataset(evaluation: full.evaluation.filter { $0.label == "neutral" },
            participantID: profile.participantID, records: [], sessions: full.sessions)
        let report = try EEGLabeledEvaluation.run(profile: profile, dataset: dataset, controlsOnly: true)
        let manifest = Data("synthetic internal serialization test".utf8)
        let receipt = try EEGEvaluationArtifact.make(report: report, dataset: dataset, manifest: manifest, profile: profile)
        XCTAssertEqual(receipt.data, try EEGEvaluationArtifact.make(report: report, dataset: dataset, manifest: manifest, profile: profile).data)
        let object = try JSONSerialization.jsonObject(with: receipt.data) as! [String: Any]
        XCTAssertEqual(object["controls_only"] as? Bool, true)
        XCTAssertEqual(object["algorithm_version"] as? String,"native-labeled-evaluation-12")
        let confusion = object["confusion"] as! [String: [String: Any]]
        XCTAssertEqual(confusion.values.reduce(0) { $0 + ($1["actual_windows"] as! Int) }, report.predictions.count)
        let sessionConfusion = object["session_confusion"] as! [String: [String: [String: Any]]]
        for (session, rows) in sessionConfusion {
            XCTAssertEqual(rows.values.reduce(0) { $0 + ($1["actual_windows"] as! Int) }, report.predictions.filter { $0.sessionID == session }.count)
        }
        let sessions = try XCTUnwrap(object["session_conditions"] as? [String: [String: [String: Any]]])
        XCTAssertEqual(Set(sessions.keys),Set(report.sessionConditions.keys))
        for (session, conditions) in report.sessionConditions {
            for (condition, exposure) in conditions {
                let saved = try XCTUnwrap(sessions[session]?[condition])
                XCTAssertEqual(saved["eligible_seconds"] as? Double,exposure.eligibleSeconds)
                XCTAssertEqual(saved["episode_onsets"] as? Int,exposure.episodeOnsets)
            }
        }
        if let parent = profile.parentProfileID { XCTAssertEqual(object["parent_profile_id"] as? String,parent) }
        else { XCTAssertTrue(object["parent_profile_id"] is NSNull) }
        let trialMetrics = try XCTUnwrap(object["trial_metrics"] as? [String: [String: Any]])
        for (label, metric) in report.trialMetrics {
            XCTAssertEqual(trialMetrics[label]?["declared_trials"] as? Int, metric.declaredTrials)
            XCTAssertEqual(trialMetrics[label]?["unavailable_trials"] as? Int, metric.unavailableTrials)
            XCTAssertTrue(trialMetrics[label]?["observation_fraction"] is NSNull) // Fixture cues are absent.
        }
        let sessionTrials = try XCTUnwrap(object["session_trial_metrics"] as? [String: [String: [String: Any]]])
        XCTAssertEqual(Set(sessionTrials.keys), Set(report.sessionTrialMetrics.keys))
        let metrics = object["metrics"] as! [String: [String: Any]]
        XCTAssertTrue(metrics["task"]!["recall"] is NSNull)
        XCTAssertTrue(metrics["task"]!["rejection_fraction"] is NSNull)
        XCTAssertEqual(metrics["task"]!["actual_windows"] as? Int,0)
        XCTAssertEqual(metrics["neutral"]!["rejected_windows"] as? Int,10)
        XCTAssertEqual(metrics["neutral"]!["rejection_fraction"] as? Double,1)
        let predictions = object["predictions"] as! [[String: Any]]
        for (serialized, expected) in zip(predictions, report.predictions) {
            if let label = expected.predictedLabel { XCTAssertEqual(serialized["predicted_label"] as? String, label) }
            else { XCTAssertTrue(serialized["predicted_label"] is NSNull) }
            XCTAssertEqual(serialized["reason"] as? String, expected.reason)
        }
        XCTAssertTrue(object["session_resampling"] is NSNull)
        let resampled = try EEGEvaluationArtifact.make(report: report, dataset: dataset, manifest: manifest,
            profile: profile, resampling: .init(iterations: 100, seed: 42))
        let resampledObject = try JSONSerialization.jsonObject(with: resampled.data) as! [String: Any]
        let serializedResampling = try XCTUnwrap(resampledObject["session_resampling"] as? [String: [String: Any]])
        XCTAssertEqual(serializedResampling["neutral"]?["status"] as? String,"insufficient_sessions")
        XCTAssertEqual(resampled.sessionResampling?["neutral"]?.options.seed,42)
        XCTAssertFalse(resampled.report.systemControlEnabled)
        let trials = object["trials"] as! [[String: Any]]
        XCTAssertTrue(trials.allSatisfy { $0["cue_completed_at_seconds"] is NSNull })
        XCTAssertTrue(trials.allSatisfy { $0["scored_target_detected"] is NSNull && $0["scored_neutral_false_positive"] is NSNull })
        for (saved, trial) in zip(trials, report.trials) {
            XCTAssertEqual(saved["eligible_fraction"] as? Double, trial.eligibleFraction)
            XCTAssertEqual(saved["contained_candidate_windows"] as? Int, trial.containedCandidateWindows)
        }
    }

}
