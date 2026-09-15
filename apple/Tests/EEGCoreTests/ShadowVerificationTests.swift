import Foundation
import XCTest
@testable import EEGCore

final class ShadowVerificationTests: XCTestCase {
    private func profile() throws -> EEGMentalProfile {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try EEGMentalProfile.load(data:Data(contentsOf:root.appendingPathComponent("Fixtures/spectrum/mental-profile.json")))
    }
    private func capture(_ store:EEGRecordingStore,profile:EEGMentalProfile,mutate:Bool=false,omit:Bool=false,stop:Bool=true,finalized:Bool=true,identity:[String:String]=[:]) throws -> URL {
        let writerQueue=DispatchQueue(label:"test.shadow.recording")
        let writer=try EEGQueuedRecordingStore(store:store,queue:writerQueue) {_,reason in
            XCTFail("Unexpected recording failure: \(reason)")
        }
        let url=try writer.start()
        // Hold the real recording queue while live inference proceeds. This
        // checks that event/sample admission order survives deferred storage.
        writerQueue.suspend();var suspended=true
        defer {if suspended {writerQueue.resume()};writer.abort();writerQueue.sync {}}
        let metadata=["81072f44-9f3d-11e3-a9dc-0002a5d5c51b":"018000102010"]
        try writer.enqueueEvent(kind:"device_metadata",fields:metadata)
        try writer.enqueueEvent(kind:"transport_status",fields:["status":"stable"])
        func sample(_ i:Int)->EEGSample {
            let word=UInt16(31200+Int(50*sin(Double(i)*0.5)))
            return EEGSample(index:i,counter:i%128,receivedAt:Double(i)/128,continuous:true,
                adcWords:Array(repeating:word,count:15),
                electrodesADC:Dictionary(uniqueKeysWithValues:EEGRecordingStore.channels.map {($0,Double(word))}),
                electrodesMicrovolts:Dictionary(uniqueKeysWithValues:EEGRecordingStore.channels.map {($0,Double(word)/7.8)}),
                notificationSlot:0,recordFlag:0)
        }
        for i in 0..<13 {try writer.enqueue(sample:sample(i))}
        try writer.enqueueEvent(kind:"shadow_start",fields:["shadow_run_id":"run","profile_id":profile.id,
            "participant_id":profile.participantID,"session_id":"held-out","feature_config_id":EEGMentalFeatures.configurationID,
            "system_control_enabled":"false"].merging(identity) {_,new in new})
        let queue=DispatchQueue(label:"test.shadow.reference")
        var results=[EEGWindowInferenceResult]()
        let live=try EEGLiveInference(profile:profile,participantID:profile.participantID,sessionID:"held-out",
            maximumPendingInputs:512,queue:queue) {if let row=$0.window {results.append(row)}}
        live.submit(.event(try JSONSerialization.data(withJSONObject:metadata.merging(["kind":"device_metadata"]) {_,v in v})))
        live.submit(.event(Data("{\"kind\":\"transport_status\",\"status\":\"stable\"}".utf8)))
        for i in 13..<269 {let row=sample(i);try writer.enqueue(sample:row);XCTAssertTrue(live.submit(.sample(row)))}
        queue.sync {};live.stop()
        XCTAssertEqual(results.count,1)
        if !omit,let row=results.first {
            try writer.enqueueEvent(kind:"shadow_inference",fields:["shadow_run_id":"run","profile_id":profile.id,
                "session_id":"held-out","feature_config_id":EEGMentalFeatures.configurationID,"generation":"0",
                "ordinal":String(row.ordinal),"candidate":mutate ? "fabricated" : (row.candidate ?? ""),
                "has_candidate":String(row.candidate != nil),"status":row.status,"system_control_enabled":"false",
                "reasons":row.reasons.joined(separator:";"),"first_sample_index":String(row.firstSampleIndex!),
                "last_sample_index":String(row.lastSampleIndex!),"sample_count":String(row.sampleCount),
                "input_start":String(row.inputStart!),"input_end":String(row.inputEnd!),"time_basis":"recorded_receipt_seconds"])
        }
        if stop {try writer.enqueueEvent(kind:"shadow_stop",fields:["shadow_run_id":"run","reason":"operator_stopped"])}
        writerQueue.resume();suspended=false
        if finalized {try writer.finish()} else {writer.abort();writerQueue.sync {}};return url
    }
    func testRecordedImplementationIdentityIsSeparateFromOutputAgreement() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let store=try EEGRecordingStore(directory:directory),profile=try profile()
        func verify(_ fields:[String:String]) throws -> EEGShadowVerification.Report {
            let url=try capture(store,profile:profile,identity:fields)
            return try EEGShadowVerification.run(store:store,recording:url,profile:profile,runID:"run")
        }
        let fields=EEGShadowVerification.implementationFields
        let matching=try verify(fields)
        XCTAssertTrue(matching.completeMatch);XCTAssertTrue(matching.sameImplementationMatch)
        XCTAssertEqual(matching.implementationStatus,.matchingSource)
        XCTAssertEqual(matching.recordedImplementationSHA256,EEGSourceIdentity.sha256)
        let absent=try verify([:])
        XCTAssertTrue(absent.completeMatch);XCTAssertFalse(absent.sameImplementationMatch)
        XCTAssertEqual(absent.implementationStatus,.unavailable)
        XCTAssertNil(absent.recordedImplementationSHA256)
        var different=fields
        different["implementation_source_sha256"]=String(repeating:EEGSourceIdentity.sha256.first == "a" ? "b" : "a",count:64)
        let changed=try verify(different)
        XCTAssertTrue(changed.completeMatch);XCTAssertFalse(changed.sameImplementationMatch)
        XCTAssertEqual(changed.implementationStatus,.differentSource)
        different=fields;different["implementation_source_input_count"]=String(EEGSourceIdentity.inputFileCount+1)
        XCTAssertEqual(try verify(different).implementationStatus,.differentSource)
        for key in fields.keys {
            var partial=fields;partial.removeValue(forKey:key)
            XCTAssertThrowsError(try verify(partial))
        }
        for (key,value) in [("implementation_source_sha256","invalid"),
                            ("implementation_source_input_count","0"),
                            ("implementation_source_input_count","01"),
                            ("implementation_source_schema","unknown")] {
            var invalid=fields;invalid[key]=value
            XCTAssertThrowsError(try verify(invalid))
        }
    }
    func testLiveRunBoundaryAlignmentAndChangedOutput() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let store=try EEGRecordingStore(directory:directory),profile=try profile()
        let url=try capture(store,profile:profile)
        let report=try EEGShadowVerification.run(store:store,recording:url,profile:profile,runID:"run")
        XCTAssertTrue(report.completeMatch);XCTAssertEqual(report.replayWindows,1)
        XCTAssertEqual(report.recordedWindows,1);XCTAssertFalse(report.systemControlEnabled)
        let changed=try capture(store,profile:profile,mutate:true)
        let mismatch=try EEGShadowVerification.run(store:store,recording:changed,profile:profile,runID:"run")
        XCTAssertFalse(mismatch.completeMatch);XCTAssertEqual(mismatch.mismatchedOrdinals,[0])
    }
    func testCatalogPinsSelectionAndRejectsDuplicateRunIDs() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let store=try EEGRecordingStore(directory:directory),profile=try profile()
        let url=try capture(store,profile:profile)
        let catalog=try EEGShadowVerification.catalog(store:store,recording:url)
        XCTAssertEqual(catalog.runs.map(\.id),["run"])
        XCTAssertEqual(catalog.runs.first?.sessionID,"held-out")
        XCTAssertEqual(catalog.runs.first?.profileID,profile.id)
        XCTAssertTrue(try EEGShadowVerification.run(store:store,recording:url,profile:profile,runID:"run",
            expectedRecordingSHA256:catalog.recordingSHA256).completeMatch)
        var rows=try String(contentsOf:url).split(separator:"\n").map(String.init)
        rows.insert("{\"kind\":\"annotation\",\"text\":\"changed after discovery\"}",at:rows.count-1)
        try (rows.joined(separator:"\n")+"\n").write(to:url,atomically:false,encoding:.utf8)
        XCTAssertThrowsError(try EEGShadowVerification.run(store:store,recording:url,profile:profile,runID:"run",
            expectedRecordingSHA256:catalog.recordingSHA256))
        XCTAssertTrue(try EEGShadowVerification.run(store:store,recording:url,profile:profile,runID:"run").completeMatch)
        let start=try XCTUnwrap(rows.first(where:{$0.contains("shadow_start")}))
        rows.insert(start,at:rows.count-1)
        try (rows.joined(separator:"\n")+"\n").write(to:url,atomically:false,encoding:.utf8)
        XCTAssertThrowsError(try EEGShadowVerification.catalog(store:store,recording:url))
        XCTAssertThrowsError(try EEGShadowVerification.catalog(store:store,recording:url,maximumRuns:0))
        let empty=try store.start();try store.finish()
        XCTAssertTrue(try EEGShadowVerification.catalog(store:store,recording:empty).runs.isEmpty)
    }
    func testActiveRunCannotHideTransportOrConfigurationEvents() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let store=try EEGRecordingStore(directory:directory),profile=try profile()
        let url=try capture(store,profile:profile)
        let original=try String(contentsOf:url).split(separator:"\n").map(String.init)
        let events = [
            "{\"kind\":\"transport_status\",\"status\":\"recovering\"}",
            "{\"kind\":\"decode_error\",\"message\":\"injected packet rejection\"}",
            "{\"kind\":\"connection_error\",\"message\":\"injected disconnection\"}",
            "{\"kind\":\"device_metadata\",\"81072f44-9f3d-11e3-a9dc-0002a5d5c51b\":\"unsupported\"}"
        ]
        let start=try XCTUnwrap(original.firstIndex(where:{$0.contains("shadow_start")}))
        let stop=try XCTUnwrap(original.firstIndex(where:{$0.contains("shadow_stop")}))
        for event in events {
            for insertion in [start+1,stop] {
                var rows=original;rows.insert(event,at:insertion)
                try (rows.joined(separator:"\n")+"\n").write(to:url,atomically:false,encoding:.utf8)
                XCTAssertThrowsError(try EEGShadowVerification.run(store:store,recording:url,profile:profile,runID:"run")) {
                    guard case EEGShadowVerification.Failure.invalidRun = $0 else { return XCTFail("Unexpected: \($0)") }
                }
            }
            // The native host stops the run before persisting the fault; later
            // lifecycle events must not retroactively invalidate a completed run.
            var rows=original;rows.insert(event,at:stop+1)
            try (rows.joined(separator:"\n")+"\n").write(to:url,atomically:false,encoding:.utf8)
            XCTAssertTrue(try EEGShadowVerification.run(store:store,recording:url,profile:profile,runID:"run").completeMatch)
        }
    }
    func testRunRequiresRecordedStableTransportBeforeStart() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let store=try EEGRecordingStore(directory:directory),profile=try profile()
        let url=try capture(store,profile:profile)
        let original=try String(contentsOf:url).split(separator:"\n").map(String.init)
        let index=try XCTUnwrap(original.firstIndex(where:{$0.contains("transport_status")}))
        for replacement in [nil,"{\"kind\":\"transport_status\",\"status\":\"recovering\"}",
                            "{\"kind\":\"decode_error\"}","{\"kind\":\"connection_error\"}"] as [String?] {
            var rows=original;rows.remove(at:index)
            if let replacement {rows.insert(replacement,at:index)}
            try (rows.joined(separator:"\n")+"\n").write(to:url,atomically:false,encoding:.utf8)
            XCTAssertThrowsError(try EEGShadowVerification.run(store:store,recording:url,profile:profile,runID:"run"))
        }
        for kind in ["decode_error","connection_error"] {
            var rows=original
            let start=try XCTUnwrap(rows.firstIndex(where:{$0.contains("shadow_start")}))
            rows.insert("{\"kind\":\"\(kind)\"}",at:start)
            try (rows.joined(separator:"\n")+"\n").write(to:url,atomically:false,encoding:.utf8)
            XCTAssertThrowsError(try EEGShadowVerification.run(store:store,recording:url,profile:profile,runID:"run"))
            rows.insert("{\"kind\":\"transport_status\",\"status\":\"stable\"}",at:start+1)
            try (rows.joined(separator:"\n")+"\n").write(to:url,atomically:false,encoding:.utf8)
            XCTAssertTrue(try EEGShadowVerification.run(store:store,recording:url,profile:profile,runID:"run").completeMatch)
        }
    }
    func testSingleActiveRunOrderingAndSequentialRuns() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let store=try EEGRecordingStore(directory:directory),profile=try profile()
        let url=try capture(store,profile:profile)
        let original=try String(contentsOf:url).split(separator:"\n").map(String.init)
        let start=try XCTUnwrap(original.firstIndex(where:{$0.contains("shadow_start")}))
        let stop=try XCTUnwrap(original.firstIndex(where:{$0.contains("shadow_stop")}))
        func renamed(_ text:String) throws -> String {
            var object=try JSONSerialization.jsonObject(with:Data(text.utf8)) as! [String:Any]
            object["shadow_run_id"]="other"
            return String(decoding:try JSONSerialization.data(withJSONObject:object),as:UTF8.self)
        }
        let otherStart=try renamed(original[start]),otherStop=try renamed(original[stop])
        let inference=try XCTUnwrap(original.first(where:{$0.contains("shadow_inference")}))
        let otherInference=try renamed(inference)
        for (event,index) in [(otherStart,start),(otherStart,start+1),(otherStop,start+1),
                              (otherInference,stop),(otherStop,start),(otherInference,start)] {
            var rows=original;rows.insert(event,at:index)
            try (rows.joined(separator:"\n")+"\n").write(to:url,atomically:false,encoding:.utf8)
            XCTAssertThrowsError(try EEGShadowVerification.catalog(store:store,recording:url))
            XCTAssertThrowsError(try EEGShadowVerification.run(store:store,recording:url,profile:profile,runID:"run"))
        }
        for index in [start,stop+1] {
            var rows=original;rows.insert(contentsOf:[otherStart,otherStop],at:index)
            try (rows.joined(separator:"\n")+"\n").write(to:url,atomically:false,encoding:.utf8)
            XCTAssertEqual(try EEGShadowVerification.catalog(store:store,recording:url).runs.count,2)
            XCTAssertTrue(try EEGShadowVerification.run(store:store,recording:url,profile:profile,runID:"run").completeMatch)
            XCTAssertFalse(try EEGShadowVerification.run(store:store,recording:url,profile:profile,runID:"other").completeMatch)
        }
    }
    func testMissingOutputAndMissingStopNeverPass() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let store=try EEGRecordingStore(directory:directory),profile=try profile()
        let missing=try capture(store,profile:profile,omit:true)
        let report=try EEGShadowVerification.run(store:store,recording:missing,profile:profile,runID:"run")
        XCTAssertFalse(report.completeMatch);XCTAssertEqual(report.missingOrdinals,[0])
        let noStop=try capture(store,profile:profile,stop:false)
        XCTAssertFalse(try EEGShadowVerification.run(store:store,recording:noStop,profile:profile,runID:"run").completeMatch)
        XCTAssertThrowsError(try EEGShadowVerification.run(store:store,recording:noStop,profile:profile,runID:"absent"))
        let incomplete=try capture(store,profile:profile,finalized:false)
        XCTAssertThrowsError(try EEGShadowVerification.catalog(store:store,recording:incomplete))
        XCTAssertThrowsError(try EEGShadowVerification.run(store:store,recording:incomplete,profile:profile,runID:"run"))
        XCTAssertThrowsError(try EEGShadowVerification.run(store:store,recording:noStop,profile:profile,runID:"run",maximumWindows:0))
    }
}
