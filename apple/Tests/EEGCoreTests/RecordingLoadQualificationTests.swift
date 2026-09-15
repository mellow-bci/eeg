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
}
