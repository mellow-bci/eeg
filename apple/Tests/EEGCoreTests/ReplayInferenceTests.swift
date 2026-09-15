import Foundation
import CryptoKit
import XCTest
@testable import EEGCore

final class ReplayInferenceTests: XCTestCase {
    // Python hashlib/json oracle for 512 synthetic counter/ADC rows.
    private let contentDigest = "d7d9aa146e0d8b827a3129719ef8ee6fea55d8cc7972a12d24b5b0a473a0fc63"
    private func profileData() throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("Fixtures/spectrum/mental-profile.json"))
    }
    private func recording(_ store: EEGRecordingStore, finished: Bool = true) throws -> URL {
        let url = try store.start()
        try store.appendEvent(kind: "device_metadata", fields: ["81072f44-9f3d-11e3-a9dc-0002a5d5c51b": "018000102010"])
        try store.appendEvent(kind: "transport_status", fields: ["status": "stable"])
        for i in 0..<512 {
            let word = UInt16(31200 + Int(50 * sin(Double(i) * 0.5)))
            try store.append(sample: EEGSample(index: i, counter: i % 128, receivedAt: Double(i) / 128, continuous: true,
                adcWords: [UInt16](repeating: word, count: 15),
                electrodesADC: Dictionary(uniqueKeysWithValues: EEGRecordingStore.channels.map { ($0, Double(word)) }),
                electrodesMicrovolts: Dictionary(uniqueKeysWithValues: EEGRecordingStore.channels.map { ($0, Double(word) / 7.8) }),
                notificationSlot: 0, recordFlag: 0))
        }
        if finished { try store.finish() }
        return url
    }
    func testCompletedReplayAndLimits() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EEGRecordingStore(directory: directory), url = try recording(store)
        let profile = try EEGMentalProfile.load(data: profileData())
        let report = try EEGReplayInference.run(store: store, recording: url, profile: profile, participantID: "participant", sessionID: "held-out")
        XCTAssertEqual(report.windows.count, 2)
        XCTAssertEqual(report.eegContentSHA256, contentDigest)
        XCTAssertFalse(report.systemControlEnabled)
        XCTAssertEqual(report.status, "experimental_unvalidated")
        XCTAssertEqual(report.recordingSHA256, SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined())
        XCTAssertThrowsError(try EEGReplayInference.run(store: store, recording: url, profile: profile, participantID: "participant", sessionID: "held-out", maximumWindows: 1))
        XCTAssertThrowsError(try EEGReplayInference.run(store: store, recording: url, profile: profile, participantID: "other", sessionID: "held-out"))
        XCTAssertThrowsError(try EEGReplayInference.run(store: store, recording: url, profile: profile, participantID: "participant", sessionID: "train-a"))
    }
    func testSharedWindowProcessorMatchesReplayAndRejectsMalformedWindow() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store=try EEGRecordingStore(directory:directory),url=try recording(store)
        let profile=try EEGMentalProfile.load(data:profileData())
        var processor=try EEGWindowInference(profile:profile,participantID:"participant",sessionID:"held-out")
        var rows: [EEGWindowInferenceResult]=[]
        try store.analysisWindows(recording:url) { rows.append(processor.process($0)) }
        let replay=try EEGReplayInference.run(store:store,recording:url,profile:profile,participantID:"participant",sessionID:"held-out")
        XCTAssertEqual(rows,replay.windows)
        let malformed=processor.process(EEGAnalysisWindow(samples:[],ordinal:2,segment:nil,reasons:[]))
        XCTAssertNil(malformed.candidate);XCTAssertEqual(malformed.reasons,["invalid_analysis_window"])
        let interrupted=processor.process(EEGAnalysisWindow(samples:[],ordinal:3,segment:nil,reasons:["transport_unstable"]))
        XCTAssertEqual(interrupted.reasons,["transport_unstable"])
        XCTAssertFalse(interrupted.systemControlEnabled);XCTAssertEqual(interrupted.status,"no_reliable_command")
        XCTAssertThrowsError(try EEGWindowInference(profile:profile,participantID:"other",sessionID:"held-out"))
    }
    func testRenamedTrainingContentRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EEGRecordingStore(directory: directory), url = try recording(store)
        let digest = contentDigest
        var object = try JSONSerialization.jsonObject(with: profileData()) as! [String: Any]
        var hashes = object["training_recording_hashes"] as! [String: String]
        hashes["train-a"] = digest; object["training_recording_hashes"] = hashes
        object["profile_id"] = try ProfileCanonicalJSON.digest(JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        let profile = try EEGMentalProfile.load(data: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        XCTAssertThrowsError(try EEGReplayInference.run(store: store, recording: url, profile: profile, participantID: "participant", sessionID: "renamed")) { error in
            guard case EEGReplayInference.Failure.trainingRecording = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }
    func testUnfinishedRecordingCannotReturnPartialReport() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EEGRecordingStore(directory: directory), url = try recording(store, finished: false)
        let profile = try EEGMentalProfile.load(data: profileData())
        XCTAssertThrowsError(try EEGReplayInference.run(store: store, recording: url, profile: profile, participantID: "participant", sessionID: "held-out"))
        try store.finish()
    }
    func testMetadataAndTimestampRewriteDoesNotChangeEEGIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EEGRecordingStore(directory: directory), url = try recording(store)
        let data = try Data(contentsOf: url)
        let rewritten = try String(decoding: data, as: UTF8.self).split(separator: "\n").map { line -> String in
            var event = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
            if var sample = event["sample"] as? [String: Any] {
                sample["receivedAt"] = (sample["receivedAt"] as! Double) + 30
                event["sample"] = sample
            }
            return String(decoding: try JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]), as: UTF8.self)
        }.joined(separator: "\n") + "\n"
        try Data(rewritten.utf8).write(to: url)
        let profile = try EEGMentalProfile.load(data: profileData())
        let report = try EEGReplayInference.run(store: store, recording: url, profile: profile, participantID: "participant", sessionID: "held-out")
        XCTAssertEqual(report.eegContentSHA256, contentDigest)
        XCTAssertNotEqual(report.recordingSHA256, SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }

}
