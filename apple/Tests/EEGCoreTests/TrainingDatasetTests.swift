import Foundation
import XCTest
@testable import EEGCore

final class TrainingDatasetTests: XCTestCase {
    private func recording(_ store: EEGRecordingStore, offset: Int, windows: Int = 20, frequencyShift: Double = 0) throws -> URL {
        let url = try store.start()
        try store.appendEvent(kind: "device_metadata", fields: ["81072f44-9f3d-11e3-a9dc-0002a5d5c51b": "018000102010"])
        try store.appendEvent(kind: "transport_status", fields: ["status": "stable"])
        for i in 0..<(windows * 256) {
            let frequency = (i < 2560 ? 10.0 : 17.0) + frequencyShift
            let word = UInt16(31200 + offset + Int(50 * sin(Double(i) * 2 * .pi * frequency / 128)))
            try store.append(sample: EEGSample(index: i, counter: i % 128, receivedAt: Double(i) / 128, continuous: true,
                adcWords: [UInt16](repeating: word, count: 15),
                electrodesADC: Dictionary(uniqueKeysWithValues: EEGRecordingStore.channels.map { ($0, Double(word)) }),
                electrodesMicrovolts: Dictionary(uniqueKeysWithValues: EEGRecordingStore.channels.map { ($0, Double(word) / 7.8) }), notificationSlot: 0, recordFlag: 0))
        }
        try store.finish(); return url
    }
    private func session(_ id: String, _ url: URL, split: String = "train") -> [String: Any] {
        ["id": id, "recording": url.lastPathComponent, "split": split, "independent_session": true,
         "trials": [["id": "neutral", "label": "neutral", "start": 0, "end": 20, "accepted": true, "label_verified": true],
                    ["id": "task", "label": "task", "start": 20, "end": 40, "accepted": true, "label_verified": true]]]
    }
    private func manifest(_ sessions: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["schema": "eeg.dataset.v1", "participant_id": "synthetic", "sessions": sessions])
    }
    func testRecordingsAndLabelsTrainNativeProfileWithoutEvaluationLeakage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EEGRecordingStore(directory: directory)
        let a = try recording(store, offset: 0), b = try recording(store, offset: 10), c = try recording(store, offset: 20)
        let d = try recording(store, offset: 30)
        let manifestData = try manifest([session("a", a), session("b", b), session("c", c, split: "evaluation"), session("d", d, split: "evaluation")])
        let dataset = try EEGTrainingDataset.load(manifestData, store: store)
        XCTAssertEqual(dataset.records.count, 40)
        XCTAssertEqual(dataset.sessions.map(\.usableWindows), [20, 20, 20, 20])
        XCTAssertEqual(Set(dataset.records.map(\.session_id)), ["a", "b"])
        let artifact = try EEGProfileCreation.train(dataset.records, participantID: dataset.participantID)
        XCTAssertEqual(Set(artifact.profile.trainingSessions), ["a", "b"])
        XCTAssertFalse(try EEGReplayInference.run(store: store, recording: c, profile: artifact.profile, participantID: "synthetic", sessionID: "c").systemControlEnabled)
        let receipt = try EEGEvaluationArtifact.run(manifest: manifestData, store: store, profile: artifact.profile)
        let object = try JSONSerialization.jsonObject(with: receipt.data) as! [String: Any]
        XCTAssertEqual(receipt.trainingSourceAudit.status, "all_training_sources_present")
        XCTAssertEqual(receipt.trainingSourceAudit.matches.count, 2)
        XCTAssertEqual(object["schema"] as? String, "eeg.native-evaluation.v1")
        XCTAssertEqual(Data(base64Encoded: object["manifest_base64"] as! String), manifestData)
        XCTAssertEqual(object["profile_id"] as? String, artifact.profile.id)
        XCTAssertEqual((object["predictions"] as! [[String: Any]]).count, 40)
        let sources = object["sources"] as! [[String: Any]]
        XCTAssertEqual(sources.map { $0["file_sha256"] as! String }, dataset.sessions.map(\.fileSHA256))
        XCTAssertEqual(sources.map { $0["eeg_content_sha256"] as! String }, dataset.sessions.map(\.eegSHA256))
        XCTAssertEqual(object["system_control_enabled"] as? Bool, false)
        XCTAssertEqual(object["hardware_validated"] as? Bool, false)
        XCTAssertThrowsError(try EEGEvaluationArtifact.run(manifest: Data("{}".utf8), store: store, profile: artifact.profile))
        if let exportPath = ProcessInfo.processInfo.environment["EEG_NATIVE_EVALUATION_TEST_EXPORT"] {
            let export = URL(fileURLWithPath: exportPath, isDirectory: true)
            try FileManager.default.createDirectory(at: export, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try manifestData.write(to: export.appendingPathComponent("manifest.json"), options: .withoutOverwriting)
            try artifact.data.write(to: export.appendingPathComponent("profile.json"), options: .withoutOverwriting)
            try receipt.data.write(to: export.appendingPathComponent("expected.json"), options: .withoutOverwriting)
            for source in [a, b, c, d] {
                try FileManager.default.copyItem(at: source, to: export.appendingPathComponent(source.lastPathComponent))
            }
        }


    }
    func testHeldOutSignalAndLabelChangesCannotChangeFittedProfile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EEGRecordingStore(directory: directory)
        let a = try recording(store, offset: 0), b = try recording(store, offset: 10)
        let c = try recording(store, offset: 20)
        let changedSignal = try recording(store, offset: 30, frequencyShift: 4)
        let training = [session("a", a), session("b", b)]
        func load(_ heldOut: [[String: Any]]) throws -> EEGTrainingDataset {
            try EEGTrainingDataset.load(manifest(training + heldOut), store: store)
        }
        let baseline = try load([session("c", c, split: "evaluation")])
        let expected = try EEGProfileCreation.train(baseline.records, participantID: baseline.participantID)
        var relabeled = session("c", c, split: "evaluation")
        var trials = relabeled["trials"] as! [[String: Any]]
        trials[0]["label"] = "task"; trials[1]["label"] = "neutral"
        relabeled["trials"] = trials
        let labelChange = try load([relabeled])
        let signalChange = try load([session("different", changedSignal, split: "evaluation")])
        let noHeldOut = try load([])
        // Verify the intervention actually reaches the canonical evaluation inputs.
        XCTAssertEqual(baseline.evaluation.count, 20)
        XCTAssertEqual(labelChange.evaluation.map(\.label), baseline.evaluation.map { $0.label == "neutral" ? "task" : "neutral" })
        XCTAssertEqual(labelChange.evaluation.map { $0.input.values }, baseline.evaluation.map { $0.input.values })
        XCTAssertNotEqual(signalChange.evaluation.map { $0.input.values }, baseline.evaluation.map { $0.input.values })
        XCTAssertTrue(noHeldOut.evaluation.isEmpty)
        for dataset in [labelChange, signalChange, noHeldOut] {
            XCTAssertEqual(dataset.records.count, 40)
            let fitted = try EEGProfileCreation.train(dataset.records, participantID: dataset.participantID)
            // Includes normalization, selection, PCA, Gaussian parameters, thresholds,
            // training provenance and the profile digest, not merely session IDs.
            XCTAssertEqual(fitted.data, expected.data)
        }
    }
    func testDuplicateRecordingCannotBecomeEvaluationSession() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EEGRecordingStore(directory: directory), a = try recording(store, offset: 0)
        XCTAssertThrowsError(try EEGTrainingDataset.load(manifest([session("a", a), session("renamed", a, split: "evaluation")]), store: store)) { error in
            guard case EEGTrainingDataset.Failure.duplicateRecording = error else { return XCTFail("Unexpected: \(error)") }
        }
    }
    func testDifferentLengthRecordingWithSharedSamplesIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EEGRecordingStore(directory: directory)
        let a = try recording(store, offset: 0, windows: 20)
        let b = try recording(store, offset: 0, windows: 21)
        XCTAssertThrowsError(try EEGTrainingDataset.load(manifest([session("a", a), session("b", b, split: "evaluation")]), store: store)) { error in
            guard case EEGTrainingDataset.Failure.reusedRecordingExcerpt = error else { return XCTFail("Unexpected: \(error)") }
        }
    }
    func testUncertainOverlappingAndOutsideStoreTrialsRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EEGRecordingStore(directory: directory)
        let original = session("a", directory.appendingPathComponent("unused.jsonl"))
        for mode in 0..<5 {
            var changed = original
            var trials = changed["trials"] as! [[String: Any]]
            if mode == 0 { trials[0]["label_verified"] = false }
            if mode == 1 { trials[1]["start"] = 19 }
            if mode == 2 { changed["recording"] = "../outside.jsonl" }
            if mode == 3 { trials[0]["start"] = -1 }
            if mode == 4 { trials[0]["cue_completed_at"] = -1 }
            changed["trials"] = trials
            XCTAssertThrowsError(try EEGTrainingDataset.load(manifest([changed]), store: store)) { error in
                if mode == 2 {
                    guard case EEGTrainingDataset.Failure.invalidManifest = error else { return XCTFail("Unexpected: \(error)") }
                } else {
                    guard case EEGTrainingDataset.Failure.invalidTrial = error else { return XCTFail("Unexpected: \(error)") }
                }
            }
        }
    }
}
