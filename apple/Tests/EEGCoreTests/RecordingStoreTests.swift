import XCTest
@testable import EEGCore

final class RecordingStoreTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func sample(_ index: Int, calibrated: Bool = true) -> EEGSample {
        let values = Dictionary(uniqueKeysWithValues: EEGRecordingStore.channels.map { ($0, Double(index + 10)) })
        return EEGSample(index: index, counter: index % 128, receivedAt: Double(index) / 128,
                         continuous: true, adcWords: [UInt16](repeating: 10, count: 15), electrodesADC: values,
                         electrodesMicrovolts: calibrated ? values.mapValues { $0 / 7.8 } : nil,
                         notificationSlot: 0, recordFlag: 0)
    }
    func testAbortPreservesSamplesButPreventsCompletionAndAnalysis() throws {
        let store = try EEGRecordingStore(directory: root)
        let file = try store.start()
        try store.append(sample: sample(0))
        store.abort(); store.abort()
        XCTAssertThrowsError(try store.finish())
        XCTAssertThrowsError(try store.append(sample: sample(1)))
        let info = try XCTUnwrap(store.inventory().first)
        XCTAssertFalse(info.complete); XCTAssertFalse(info.corrupt)
        XCTAssertEqual(try store.replay(recording: file).count, 1)
        XCTAssertThrowsError(try store.analysisWindows(recording: file) { _ in })
        let next = try store.start()
        XCTAssertNotEqual(next, file)
        try store.append(sample: sample(0)); try store.finish()
        XCTAssertTrue(try XCTUnwrap(store.inventory().first { $0.name == next.lastPathComponent }).complete)
    }
    func testOversizedEventClosesRecordingWithoutSummary() throws {
        let store = try EEGRecordingStore(directory: root)
        let file = try store.start()
        try store.append(sample: sample(0))
        XCTAssertThrowsError(try store.appendEvent(kind: "annotation", fields: ["text": String(repeating: "x", count: 4 * 1024 * 1024)]))
        XCTAssertThrowsError(try store.finish())
        XCTAssertFalse(try XCTUnwrap(store.inventory().first).complete)
        XCTAssertEqual(try store.replay(recording: file).count, 1)
    }
    func testLifecycleReplayAndExport() throws {
        let store = try EEGRecordingStore(directory: root)
        XCTAssertThrowsError(try store.append(sample: sample(0)))
        let file = try store.start()
        XCTAssertThrowsError(try store.start())
        try store.appendEvent(kind: "ble_notification", fields: ["hex": "0102"])
        for index in 0..<12 { try store.append(sample: sample(index)) }
        XCTAssertFalse(try XCTUnwrap(store.inventory().first).complete)
        try store.finish()
        let info = try XCTUnwrap(store.inventory().first)
        XCTAssertTrue(info.complete); XCTAssertEqual(info.sampleCount, 12)
        XCTAssertEqual(try store.replay(recording: file, offset: 4, limit: 3).map(\.index), [4, 5, 6])
        let destination = root.appendingPathComponent("export.csv")
        try store.exportCSV(recording: file, to: destination, units: .microvolts)
        let lines = try String(contentsOf: destination).split(separator: "\n")
        XCTAssertEqual(lines.count, 13)
        XCTAssertTrue(lines[1].contains(",microvolts,"))
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
        XCTAssertThrowsError(try store.exportCSV(recording: file, to: destination))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }
    func testNativeExportPreservesCompleteAndIncompleteBytes() throws {
        let store = try EEGRecordingStore(directory: root)
        for complete in [false, true] {
            let file = try store.start()
            try store.append(sample: sample(0))
            try store.appendEvent(kind: "annotation", fields: ["text": "eyes open · observation", "receivedAt": "0.1"])
            if complete { try store.finish() } else { store.abort() }
            let destination = root.appendingPathComponent("export-\(complete).jsonl")
            try store.exportNative(recording: file, to: destination)
            XCTAssertEqual(try Data(contentsOf: destination), try Data(contentsOf: file))
            let info = try XCTUnwrap(store.inventory().first { $0.name == destination.lastPathComponent })
            XCTAssertEqual(info.complete, complete)
            XCTAssertFalse(info.corrupt)
            XCTAssertEqual(info.sampleCount, 1)
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: destination.path)[.posixPermissions] as? Int, 0o600)
            XCTAssertThrowsError(try store.exportNative(recording: file, to: destination))
            XCTAssertEqual(try Data(contentsOf: destination), try Data(contentsOf: file))
        }
    }
    func testNativeImportPreservesIdentityStatusAndRefusesCollision() throws {
        let source = try EEGRecordingStore(directory:root.appendingPathComponent("source"))
        let target = try EEGRecordingStore(directory:root.appendingPathComponent("target"))
        for complete in [false,true] {
            let file = try source.start()
            try source.append(sample:sample(0))
            if complete {try source.finish()} else {source.abort()}
            let result = try target.importNative(file)
            XCTAssertEqual(result.name,file.lastPathComponent)
            XCTAssertEqual(result.sampleCount,1)
            XCTAssertEqual(result.complete,complete)
            XCTAssertEqual(try Data(contentsOf:result.url),try Data(contentsOf:file))
            XCTAssertThrowsError(try target.importNative(file))
            XCTAssertEqual(try Data(contentsOf:result.url),try Data(contentsOf:file))
            if !complete {XCTAssertThrowsError(try target.analysisWindows(recording:result.url) {_ in})}
        }
        let corrupt = source.directory.appendingPathComponent("corrupt.jsonl")
        try Data("broken\n".utf8).write(to:corrupt)
        XCTAssertThrowsError(try target.importNative(corrupt))
        XCTAssertFalse(FileManager.default.fileExists(atPath:target.directory.appendingPathComponent(corrupt.lastPathComponent).path))
        let alias = source.directory.appendingPathComponent("alias.jsonl")
        try FileManager.default.createSymbolicLink(at:alias,withDestinationURL:corrupt)
        XCTAssertThrowsError(try target.importNative(alias))
    }
    func testNativeExportRetainsRecoverableTrialJournal() throws {
        let store = try EEGRecordingStore(directory: root)
        let file = try store.start()
        let plan = try EEGTrialPlan(sessionID:"session", participantID:"synthetic", seed:42)
        try store.appendEvent(kind:"trial_plan", fields:["json":String(decoding:try JSONEncoder().encode(plan),as:UTF8.self)])
        var trial = plan.trials[0]
        try store.appendTrialEvidence(trial)
        try trial.interrupt(reason:"synthetic_stop",at:2)
        try store.appendTrialEvidence(trial)
        try store.finish()
        let exported = try EEGRecordingStore(directory:root.appendingPathComponent("archive"))
        let destination = exported.directory.appendingPathComponent(file.lastPathComponent)
        _ = try exported.importNative(file)
        XCTAssertEqual(try Data(contentsOf:file),try Data(contentsOf:destination))
        let restored = try exported.recoveredTrials(recording:destination)
        XCTAssertEqual(restored.count,1)
        XCTAssertEqual(restored.first?.phase,.interrupted)
        XCTAssertEqual(restored.first?.id,trial.id)
    }
    func testNativeExportRejectsCorruptTailAndRemovesPartialOutput() throws {
        let store = try EEGRecordingStore(directory: root)
        let file = try store.start()
        try store.append(sample: sample(0)); store.abort()
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd(); try handle.write(contentsOf: Data("broken\n".utf8)); try handle.close()
        let destination = root.appendingPathComponent("partial.jsonl")
        XCTAssertThrowsError(try store.exportNative(recording: file, to: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
    func testMalformedPathAndMissingUnits() throws {
        let store = try EEGRecordingStore(directory: root)
        let file = try store.start()
        try store.append(sample: sample(0, calibrated: false)); try store.finish()
        let export = root.appendingPathComponent("failed.csv")
        XCTAssertThrowsError(try store.exportCSV(recording: file, to: export, units: .microvolts))
        XCTAssertFalse(FileManager.default.fileExists(atPath: export.path))
        XCTAssertThrowsError(try store.replay(recording: root.deletingLastPathComponent().appendingPathComponent("outside.jsonl")))
        let alias = root.appendingPathComponent("alias.jsonl")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: file)
        XCTAssertThrowsError(try store.replay(recording: alias))
        let corrupt = root.appendingPathComponent("broken.jsonl")
        try Data("{\"kind\":".utf8).write(to: corrupt)
        XCTAssertThrowsError(try store.replay(recording: corrupt))
        XCTAssertFalse(try XCTUnwrap(store.inventory().first { $0.name == corrupt.lastPathComponent }).complete)
    }
    func testReservedEventsCannotForgeCompletion() throws {
        let store = try EEGRecordingStore(directory: root)
        _ = try store.start()
        XCTAssertThrowsError(try store.appendEvent(kind: "summary", fields: [:]))
        XCTAssertThrowsError(try store.appendEvent(kind: "other", fields: ["kind": "summary"]))
        try store.finish()
    }
    func testInventoryRejectsForgedCompletion() throws {
        let store = try EEGRecordingStore(directory: root)
        let url = try store.start(); try store.append(sample: sample(0)); try store.finish()
        let valid = try String(contentsOf: url).split(separator: "\n").map(String.init)
        var malformedSample = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(valid[1].utf8)) as? [String: Any])
        var fields = try XCTUnwrap(malformedSample["sample"] as? [String: Any])
        fields["adcWords"] = []
        malformedSample["sample"] = fields
        let malformedRow = String(decoding: try JSONSerialization.data(withJSONObject: malformedSample), as: UTF8.self)
        let variants = [
            [valid[0], malformedRow, valid[2]],
            [],

            [valid[0], valid[1], "{\"kind\":\"summary\",\"samples\":2}"],
            [valid[0], valid[1], "{\"kind\":\"import_failed\"}", valid[2]],
            [valid[0], valid[0], valid[1], valid[2]],
            valid + [valid[2]],
            valid + ["{\"kind\":\"extra\"}"],
            [valid[0].replacingOccurrences(of: "eeg-native-v1", with: "unknown"), valid[1], valid[2]],
            [valid[0], valid[1], "{\"kind\":\"summary\",\"samples\":true}"]
        ]
        for (index, lines) in variants.enumerated() {
            let bad = root.appendingPathComponent("bad-\(index).jsonl")
            try (lines.joined(separator: "\n") + "\n").write(to: bad, atomically: false, encoding: .utf8)
            let info = try XCTUnwrap(store.inventory().first { $0.name == bad.lastPathComponent })
            XCTAssertFalse(info.complete); XCTAssertTrue(info.corrupt)
            // Even a one-sample page must reject corruption appearing later in the file.
            XCTAssertThrowsError(try store.replay(recording: bad, limit: 1))
            let export = root.appendingPathComponent("bad-\(index).csv")
            XCTAssertThrowsError(try store.exportCSV(recording: bad, to: export))
            XCTAssertFalse(FileManager.default.fileExists(atPath: export.path))
        }
        let short = sample(0)
        let badSample = EEGSample(index: short.index, counter: short.counter, receivedAt: short.receivedAt,
                                  continuous: true, adcWords: [], electrodesADC: short.electrodesADC,
                                  electrodesMicrovolts: short.electrodesMicrovolts, notificationSlot: 0, recordFlag: 0)
        _ = try store.start()
        XCTAssertThrowsError(try store.append(sample: badSample))
        try store.finish()
    }

    func testTrialJournalPreservesEveryTransitionAndSamples() throws {
        let store = try EEGRecordingStore(directory: root)
        var trial = try EEGTrialEvidence(id: "t1", sessionID: "s1", participantID: "synthetic", condition: .neutral, startingNumber: 613)
        XCTAssertThrowsError(try store.appendTrialEvidence(trial))
        let url = try store.start()
        try store.append(sample: sample(0))
        try store.appendTrialEvidence(trial)
        XCTAssertThrowsError(try store.appendTrialEvidence(trial))
        try trial.requestCue(at: 1, participantReady: true, audioCheckHeard: true, transportStable: true, recordingActive: true)
        try store.appendTrialEvidence(trial)
        try trial.cueStarted(at: 2); try store.appendTrialEvidence(trial)
        try trial.interrupt(reason: "cue failed", at: 3); try store.appendTrialEvidence(trial)
        XCTAssertThrowsError(try store.appendTrialEvidence(trial))
        XCTAssertThrowsError(try store.appendEvent(kind: "trial_evidence", fields: [:]))
        try store.append(sample: sample(1)); try store.finish()
        XCTAssertEqual(try store.replay(recording: url).map(\.index), [0, 1])
        let rows = try Data(contentsOf: url).split(separator: 10).map { try JSONSerialization.jsonObject(with: Data($0)) as! [String: Any] }
        let evidence = rows.filter { $0["kind"] as? String == "trial_evidence" }
        XCTAssertEqual(evidence.map { $0["revision"] as! Int }, [0, 1, 2, 3])
        XCTAssertTrue(evidence.allSatisfy { $0["recording_id"] as? String == url.lastPathComponent })
        XCTAssertEqual((evidence.last!["evidence"] as! [String: Any])["accepted"] as? Bool, false)
        XCTAssertTrue(try store.inventory().first!.complete)
    }
    func testTrialJournalRejectsSkippedAndChangedHistory() throws {
        let store = try EEGRecordingStore(directory: root); _ = try store.start()
        var trial = try EEGTrialEvidence(id: "t", sessionID: "s", participantID: "p", condition: .neutral, startingNumber: 123)
        try store.appendTrialEvidence(trial)
        try trial.requestCue(at: 1, participantReady: true, audioCheckHeard: true, transportStable: true, recordingActive: true)
        try trial.cueStarted(at: 2)
        XCTAssertThrowsError(try store.appendTrialEvidence(trial))
        var other = try EEGTrialEvidence(id: "t", sessionID: "s", participantID: "other", condition: .neutral, startingNumber: 123)
        try other.requestCue(at: 1, participantReady: true, audioCheckHeard: true, transportStable: true, recordingActive: true)
        XCTAssertThrowsError(try store.appendTrialEvidence(other))
        XCTAssertFalse(try store.inventory().first!.complete)
        try store.finish()
    }

    func testTrialPersistenceFailureCannotBecomeCompletedRecording() throws {
        let store = try EEGRecordingStore(directory: root); _ = try store.start()
        var trial = try EEGTrialEvidence(id: "t", sessionID: "s", participantID: "p", condition: .neutral, startingNumber: 123)
        try store.appendTrialEvidence(trial)
        try trial.interrupt(reason: String(repeating: "x", count: 4 * 1024 * 1024), at: 1)
        XCTAssertThrowsError(try store.appendTrialEvidence(trial))
        XCTAssertThrowsError(try store.finish())
        XCTAssertThrowsError(try store.append(sample: sample(0)))
        XCTAssertFalse(try store.inventory().first!.complete)
    }

}
