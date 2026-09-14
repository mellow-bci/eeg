import Foundation
import XCTest
@testable import EEGCore

final class LabeledEvaluationTests: XCTestCase {
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
}
