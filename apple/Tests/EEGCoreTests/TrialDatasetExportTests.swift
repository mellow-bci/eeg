import XCTest
@testable import EEGCore

final class TrialDatasetExportTests: XCTestCase {
    func testRecoveredManifestUsesCanonicalExtractionAndPinsSource() throws { try checkExport(controls:false) }
    func testControlsExportForEvaluationButCannotTrain() throws {
        var checked = Set<String>()
        for seed in UInt64(0)..<100 {
            let plan = try EEGTrialPlan(sessionID:"session",participantID:"synthetic",seed:seed,controls:true)
            if checked.insert(plan.trials[0].requestedCondition.rawValue).inserted { try checkExport(controls:true,seed:seed) }
            if checked.count == 4 { break }
        }
        XCTAssertEqual(checked,Set(["ordinary_activity","blink_control","jaw_control","head_movement_control"]))
    }
    private func controlProfile() throws -> EEGMentalProfile {
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let object = try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("Fixtures/spectrum/mental-training.json"))) as! [String:Any]
        var rows = object["records"] as! [[String:Any]]
        for i in rows.indices { rows[i]["participant_id"] = "synthetic" }
        let records = try JSONDecoder().decode([EEGTrainingRecord].self,from:JSONSerialization.data(withJSONObject:rows))
        return try EEGProfileCreation.train(records,participantID:"synthetic").profile
    }
    private func checkExport(controls:Bool,seed:UInt64 = 42) throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store=try EEGRecordingStore(directory:root),file=try store.start()
        let plan=try EEGTrialPlan(sessionID:"session",participantID:"synthetic",seed:seed,controls:controls)
        try store.appendEvent(kind:"trial_plan",fields:["json":String(decoding:try JSONEncoder().encode(plan),as:UTF8.self)])
        try store.appendEvent(kind:"device_metadata",fields:["81072f44-9f3d-11e3-a9dc-0002a5d5c51b":"018000102010"])
        try store.appendEvent(kind:"transport_status",fields:["status":"stable"])
        var trial=plan.trials[0];try store.appendTrialEvidence(trial)
        for i in 0..<(30*128) {
            let at=Double(i)/128
            switch i {
            case 128: try trial.requestCue(at:at,participantReady:true,audioCheckHeard:true,transportStable:true,recordingActive:true)
            case 256: try trial.cueStarted(at:at)
            case 384: try trial.cueCompleted(at:at)
            case 2944: try trial.requestEndCue(at:at)
            case 2957: try trial.endCueStarted(at:at)
            case 3200: try trial.endCueCompleted(at:at)
            case 3328: try trial.report(.attempted,at:at)
            case 3456: try trial.review(accept:true,reviewer:"synthetic operator",reason:"reported",at:at)
            default: break
            }
            if [128,256,384,2944,2957,3200,3328,3456].contains(i) { try store.appendTrialEvidence(trial) }
            let word=UInt16(31200+Int(50*sin(at*2*Double.pi*10)))
            try store.append(sample:EEGSample(index:i,counter:i%128,receivedAt:at,continuous:true,
                adcWords:Array(repeating:word,count:15),
                electrodesADC:Dictionary(uniqueKeysWithValues:EEGRecordingStore.channels.map { ($0,Double(word)) }),
                electrodesMicrovolts:Dictionary(uniqueKeysWithValues:EEGRecordingStore.channels.map { ($0,Double(word)/7.8) }),notificationSlot:0,recordFlag:0))
        }
        try store.finish()
        let source=EEGTrialDatasetExport.Source(recording:file,split:.evaluation,independenceDeclaration:"Synthetic test fixture only")
        let data=try EEGTrialDatasetExport.manifest(sources:[source],store:store)
        let dataset=try EEGTrainingDataset.load(data,store:store)
        XCTAssertEqual(dataset.participantID,"synthetic")
        XCTAssertEqual(dataset.evaluation.count,6)
        XCTAssertTrue(dataset.records.isEmpty)
        if controls {
            let profile = try controlProfile()
            let receipt = try EEGEvaluationArtifact.run(manifest:data,store:store,profile:profile,controlsOnly:true)
            XCTAssertTrue(receipt.report.controlsOnly)
            XCTAssertFalse(receipt.report.systemControlEnabled)
            XCTAssertEqual(receipt.report.predictions.count,6)
            XCTAssertTrue(receipt.report.predictions.allSatisfy { $0.actual == "neutral" })
            XCTAssertNil(receipt.report.metrics["task"]?.recall)
            let condition = plan.trials[0].requestedCondition.rawValue
            XCTAssertEqual(Set(receipt.report.conditions.keys),Set([condition]))
            let exposure = try XCTUnwrap(receipt.report.conditions[condition])
            XCTAssertEqual(exposure.eligibleSeconds + exposure.rejectedSeconds + exposure.unarmedSeconds,6 * 255.0/128,accuracy:1e-10)
            XCTAssertThrowsError(try EEGEvaluationArtifact.run(manifest:data,store:store,profile:profile))
            XCTAssertTrue(dataset.evaluation.allSatisfy { $0.label == "neutral" && $0.condition == plan.trials[0].requestedCondition.rawValue })
            XCTAssertThrowsError(try EEGTrialDatasetExport.manifest(sources:[.init(recording:file,split:.train,independenceDeclaration:"synthetic")],store:store)) { error in
                guard case EEGTrialDatasetExport.Failure.controlTraining = error else { return XCTFail("Unexpected: \(error)") }
            }
        }
        XCTAssertThrowsError(try EEGTrialDatasetExport.manifest(sources:[source,source],store:store))
        XCTAssertThrowsError(try EEGTrialDatasetExport.manifest(sources:[.init(recording:file,split:.train,independenceDeclaration:" ")],store:store))
        let original=try String(contentsOf:file)
        try original.replacingOccurrences(of:"reported",with:"changed").write(to:file,atomically:true,encoding:.utf8)
        XCTAssertThrowsError(try EEGTrainingDataset.load(data,store:store))
    }
}
