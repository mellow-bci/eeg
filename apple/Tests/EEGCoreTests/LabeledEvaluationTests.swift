import Foundation
import XCTest
@testable import EEGCore

final class LabeledEvaluationTests: XCTestCase {
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
    private func file(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("Fixtures/spectrum/" + name))
    }
    private func fixture() throws -> (EEGMentalProfile, EEGTrainingDataset, [String: Any]) {
        let profile = try EEGMentalProfile.load(data: file("mental-profile.json"))
        let object = try JSONSerialization.jsonObject(with: file("mental-evaluation.json")) as! [String: Any]
        let rows = object["records"] as! [[String: Any]]
        let windows = try rows.map { row -> EEGTrainingDataset.EvaluationWindow in
            let input = try JSONDecoder().decode(EEGInferenceWindow.self, from: JSONSerialization.data(withJSONObject: row))
            return .init(input: input, label: row["label"] as! String, trialID: row["trial_id"] as! String,
                condition: row["condition"] as! String, shadowEnabled: row["shadow_enabled"] as! Bool,
                trialStart: row["trial_start"] as! Double, trialEnd: row["trial_end"] as! Double, cueCompletedAt: nil)
        }
        let summary = EEGTrainingDataset.SessionSummary(id: "evaluation", split: "evaluation", fileSHA256: "unused",
            eegSHA256: rows[0]["recording_content_sha256"] as! String, usableWindows: 19, rejectedWindows: 1)
        return (profile, EEGTrainingDataset(evaluation: windows, participantID: profile.participantID, records: [], sessions: [summary]), object["expected"] as! [String: Any])
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
        XCTAssertEqual(object["algorithm_version"] as? String,"native-labeled-evaluation-2")
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
        let trials = object["trials"] as! [[String: Any]]
        XCTAssertTrue(trials.allSatisfy { $0["cue_completed_at_seconds"] is NSNull })
    }

}
