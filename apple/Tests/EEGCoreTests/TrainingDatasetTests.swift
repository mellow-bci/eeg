import Foundation
import XCTest
@testable import EEGCore

final class TrainingDatasetTests: XCTestCase {
    private func recording(_ store: EEGRecordingStore, offset: Int, windows: Int = 20) throws -> URL {
        let url = try store.start()
        try store.appendEvent(kind: "device_metadata", fields: ["81072f44-9f3d-11e3-a9dc-0002a5d5c51b": "018000102010"])
        try store.appendEvent(kind: "transport_status", fields: ["status": "stable"])
        for i in 0..<(windows * 256) {
            let frequency = i < 2560 ? 10.0 : 17.0
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
        let dataset = try EEGTrainingDataset.load(manifest([session("a", a), session("b", b), session("c", c, split: "evaluation")]), store: store)
        XCTAssertEqual(dataset.records.count, 40)
        XCTAssertEqual(dataset.sessions.map(\.usableWindows), [20, 20, 20])
        XCTAssertEqual(Set(dataset.records.map(\.session_id)), ["a", "b"])
        let artifact = try EEGProfileCreation.train(dataset.records, participantID: dataset.participantID)
        XCTAssertEqual(Set(artifact.profile.trainingSessions), ["a", "b"])
        XCTAssertFalse(try EEGReplayInference.run(store: store, recording: c, profile: artifact.profile, participantID: "synthetic", sessionID: "c").systemControlEnabled)
    }
    func testDuplicateRecordingCannotBecomeEvaluationSession() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EEGRecordingStore(directory: directory), a = try recording(store, offset: 0)
        XCTAssertThrowsError(try EEGTrainingDataset.load(manifest([session("a", a), session("renamed", a, split: "evaluation")]), store: store)) { error in
            guard case EEGTrainingDataset.Failure.duplicateRecording = error else { return XCTFail("Unexpected: \(error)") }
        }
    }
    func testUncertainOverlappingAndOutsideStoreTrialsRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EEGRecordingStore(directory: directory)
        let original = session("a", directory.appendingPathComponent("unused.jsonl"))
        for mode in 0..<3 {
            var changed = original
            var trials = changed["trials"] as! [[String: Any]]
            if mode == 0 { trials[0]["label_verified"] = false }
            if mode == 1 { trials[1]["start"] = 19 }
            if mode == 2 { changed["recording"] = "../outside.jsonl" }
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
