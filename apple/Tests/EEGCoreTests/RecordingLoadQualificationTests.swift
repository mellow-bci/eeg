import Foundation
import XCTest
@testable import EEGCore

/// Opt-in host qualification, not a timing-sensitive CI assertion. No headset,
/// physiological labels, vendor runtime or application events are involved.
final class RecordingLoadQualificationTests: XCTestCase {
    func testPacedRecordingLoad() throws {
        let environment=ProcessInfo.processInfo.environment
        guard let reportPath=environment["EEG_RECORDING_LOAD_REPORT"] else {
            throw XCTSkip("Set EEG_RECORDING_LOAD_REPORT to run paced host qualification")
        }
        let duration=Double(environment["EEG_RECORDING_LOAD_SECONDS"] ?? "10")
        guard let duration,duration.isFinite,duration>=1,duration<=3600 else {
            return XCTFail("Duration must be 1...3600 seconds")
        }
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        var reports=[[String:Any]]()
        for rate in [128,512] {
            let raw=try EEGRecordingStore(directory:directory)
            let writer=try EEGQueuedRecordingStore(directory:directory) {_,reason in
                XCTFail("Unexpected load failure: \(reason)")
            }
            let url=try writer.start()
            let count=Int(duration*Double(rate))
            let start=ProcessInfo.processInfo.systemUptime
            var admissions=[Double](),lateness=[Double]()
            admissions.reserveCapacity(count);lateness.reserveCapacity(count)
            for index in 0..<count {
                let deadline=start+Double(index)/Double(rate)
                let remaining=deadline-ProcessInfo.processInfo.systemUptime
                if remaining>0 {Thread.sleep(forTimeInterval:remaining)}
                lateness.append(max(0,ProcessInfo.processInfo.systemUptime-deadline))
                let began=ProcessInfo.processInfo.systemUptime
                // A synthetic event plus one sample at every tick: deliberately
                // explicit workload, not a claim about BLE packet packing.
                try writer.enqueueEvent(kind:"qualification_input",fields:["synthetic":"true","index":String(index)])
                let words=(0..<15).map {UInt16(100+($0+index)%200)}
                let electrodes=Dictionary(uniqueKeysWithValues:EEGRecordingStore.channels.enumerated().map {
                    ($0.element,Double(100+($0.offset+index)%200))
                })
                try writer.enqueue(sample:EEGSample(index:index,counter:index%128,
                    receivedAt:Double(index)/Double(rate),continuous:true,adcWords:words,
                    electrodesADC:electrodes,electrodesMicrovolts:nil,notificationSlot:0,recordFlag:0))
                admissions.append(ProcessInfo.processInfo.systemUptime-began)
            }
            let drainedAt=ProcessInfo.processInfo.systemUptime
            try writer.finish()
            let finishSeconds=ProcessInfo.processInfo.systemUptime-drainedAt
            let elapsed=ProcessInfo.processInfo.systemUptime-start
            var verified=0
            _=try raw.finalizedRecords(recording:url) { _,measurement in
                guard let sample=measurement else {return}
                let index=verified;verified+=1
                XCTAssertEqual(sample.index,index)
                XCTAssertEqual(sample.counter,index%128)
                XCTAssertEqual(sample.receivedAt,Double(index)/Double(rate))
                XCTAssertEqual(sample.adcWords,(0..<15).map {UInt16(100+($0+index)%200)})
                for (channel,name) in EEGRecordingStore.channels.enumerated() {
                    XCTAssertEqual(sample.electrodesADC[name],Double(100+(channel+index)%200))
                }
            }
            XCTAssertEqual(verified,count)
            let stats=writer.statistics
            XCTAssertEqual(stats.writtenInputs,count*2)
            XCTAssertEqual(stats.discardedInputs,0)
            XCTAssertEqual(stats.failedWrites,0)
            XCTAssertEqual(stats.pendingInputs,0)
            XCTAssertFalse(stats.failed)
            func percentile(_ values:[Double],_ p:Double)->Double {
                let sorted=values.sorted();return sorted[Int(Double(sorted.count-1)*p)]
            }
            reports.append([
                "samples_per_second_requested":rate,"samples_verified":verified,
                "synthetic_events_per_sample":1,"elapsed_seconds_including_finish":elapsed,
                "admission_seconds_p50":percentile(admissions,0.5),
                "admission_seconds_p99":percentile(admissions,0.99),
                "admission_seconds_max":admissions.max()!,
                "producer_lateness_seconds_p99":percentile(lateness,0.99),
                "finish_drain_seconds":finishSeconds,
                "peak_pending_inputs":stats.peakPendingInputs,
                "peak_pending_logical_bytes":stats.peakPendingPayloadBytes,
                "maximum_queue_wait_seconds":stats.maximumQueueWaitSeconds,
                "maximum_write_seconds":stats.maximumWriteSeconds,
                "written_inputs":stats.writtenInputs,"discarded_inputs":stats.discardedInputs,
                "failed_writes":stats.failedWrites])
        }
        let report:[String:Any]=[
            "schema":"eeg.recording-load-qualification.v1",
            "input":"synthetic; no headset or physiology",
            "os":ProcessInfo.processInfo.operatingSystemVersionString,
            "processor_count":ProcessInfo.processInfo.processorCount,
            "duration_seconds_per_rate":duration,
            "build":"Swift test; caller must record configuration and revision",
            "timing_basis":"process_monotonic",
            "limitations":["Not BLE throughput or end-to-end latency", "Not a long-duration memory qualification",
                "Logical payload bytes are not process RSS", "Producer construction time is included in admission timing",
                "Host scheduling and storage load affect results", "512 Hz is synthetic stress, not a supported headset mode"],
            "runs":reports]
        let output=URL(fileURLWithPath:reportPath)
        // Do not silently overwrite an earlier qualification report.
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output,options:.withoutOverwriting)
    }
    func testPacedRecordingWithInference() throws {
        let environment=ProcessInfo.processInfo.environment
        guard let reportPath=environment["EEG_CONCURRENT_LOAD_REPORT"] else {
            throw XCTSkip("Set EEG_CONCURRENT_LOAD_REPORT for concurrent qualification")
        }
        guard let duration=Double(environment["EEG_RECORDING_LOAD_SECONDS"] ?? "10"),
              duration.isFinite,duration>=2,duration<=3600 else {return XCTFail("Duration must be 2...3600 seconds")}
        let fixture=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/spectrum/mental-profile.json")
        let profile=try EEGMentalProfile.load(data:Data(contentsOf:fixture))
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let writer=try EEGQueuedRecordingStore(directory:directory) {_,reason in XCTFail(reason)}
        let url=try writer.start()
        let queue=DispatchQueue(label:"qualification.concurrent.inference")
        var results=[EEGWindowInferenceResult](),delays=[Double]()
        let start=ProcessInfo.processInfo.systemUptime
        let consumer=try EEGLiveInference(profile:profile,participantID:profile.participantID,sessionID:"synthetic-concurrent",
            maximumPendingInputs:512,queue:queue) {output in
            XCTAssertNil(output.failure)
            guard let window=output.window else {return}
            results.append(window)
            if let end=window.inputEnd {delays.append(ProcessInfo.processInfo.systemUptime-start-end)}
            do {try writer.enqueueEvent(kind:"qualification_inference",fields:["ordinal":String(window.ordinal),"synthetic":"true"])}
            catch {XCTFail("Inference result recording failed: \(error)")}
        }
        defer {consumer.stop()}
        let metadata=["81072f44-9f3d-11e3-a9dc-0002a5d5c51b":"018000102010"]
        try writer.enqueueEvent(kind:"device_metadata",fields:metadata)
        try writer.enqueueEvent(kind:"transport_status",fields:["status":"stable"])
        XCTAssertTrue(consumer.submit(.event(try JSONSerialization.data(withJSONObject:metadata.merging(["kind":"device_metadata"]) {_,new in new}))))
        XCTAssertTrue(consumer.submit(.event(Data("{\"kind\":\"transport_status\",\"status\":\"stable\"}".utf8))))
        let count=Int(duration*128)
        var admission=[Double](),peakPending=0
        for index in 0..<count {
            let remaining=start+Double(index)/128-ProcessInfo.processInfo.systemUptime
            if remaining>0 {Thread.sleep(forTimeInterval:remaining)}
            let began=ProcessInfo.processInfo.systemUptime
            let word=UInt16(31200+Int(50*sin(Double(index)*0.5)))
            let adc=Dictionary(uniqueKeysWithValues:EEGRecordingStore.channels.map {($0,Double(word))})
            let sample=EEGSample(index:index,counter:index%128,receivedAt:Double(index)/128,continuous:true,
                adcWords:[UInt16](repeating:word,count:15),electrodesADC:adc,
                electrodesMicrovolts:adc.mapValues {$0/7.8},notificationSlot:0,recordFlag:0)
            try writer.enqueue(sample:sample)
            XCTAssertTrue(consumer.submit(.sample(sample)))
            peakPending=max(peakPending,consumer.pendingInputs)
            admission.append(ProcessInfo.processInfo.systemUptime-began)
        }
        queue.sync {}
        let beforeFinish=ProcessInfo.processInfo.systemUptime
        try writer.finish()
        let finishSeconds=ProcessInfo.processInfo.systemUptime-beforeFinish
        let store=try EEGRecordingStore(directory:directory)
        let replay=try EEGReplayInference.run(store:store,recording:url,profile:profile,
            participantID:profile.participantID,sessionID:"synthetic-concurrent",maximumWindows:count/256+1)
        // A trailing partial window exists only in finalized replay; live input
        // has not received it as a complete window.
        XCTAssertEqual(results,Array(replay.windows.prefix(results.count)))
        XCTAssertEqual(results.count,count/256)
        var verified=0
        _=try store.finalizedRecords(recording:url) {_,sample in
            guard let sample else {return}
            XCTAssertEqual(sample.index,verified)
            XCTAssertEqual(sample.receivedAt,Double(verified)/128)
            let word=UInt16(31200+Int(50*sin(Double(verified)*0.5)))
            XCTAssertEqual(sample.adcWords,[UInt16](repeating:word,count:15))
            verified+=1
        }
        XCTAssertEqual(verified,count)
        let stats=writer.statistics
        XCTAssertEqual(stats.writtenInputs,2+count+results.count)
        XCTAssertEqual(stats.failedWrites,0);XCTAssertEqual(stats.discardedInputs,0)
        XCTAssertEqual(consumer.pendingInputs,0)
        func p99(_ values:[Double])->Double {values.sorted()[Int(Double(values.count-1)*0.99)]}
        let report:[String:Any]=[
            "schema":"eeg.concurrent-load-qualification.v1","synthetic":true,"hardware_validated":false,
            "duration_seconds":duration,"samples_verified":verified,"windows_matched_to_replay":results.count,
            "profile_id":profile.id,"os":ProcessInfo.processInfo.operatingSystemVersionString,
            "admission_seconds_p99":p99(admission),"inference_availability_delay_seconds_p99":p99(delays),
            "inference_availability_delay_seconds_max":delays.max()!,"finish_drain_seconds":finishSeconds,
            "observed_peak_pending_inference_inputs":peakPending,"peak_pending_recording_inputs":stats.peakPendingInputs,
            "written_inputs":stats.writtenInputs,"failed_writes":stats.failedWrites,"discarded_inputs":stats.discardedInputs,
            "limitations":["Synthetic 128 Hz receipt schedule, not Bluetooth", "No app main-queue presentation or audio timing",
                "Delay includes producer scheduling plus worker processing; not isolated classifier time",
                "No physiological validity; artifact/model rejections remain legitimate outputs", "No process RSS measurement"]]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:reportPath),options:.withoutOverwriting)
    }

}
