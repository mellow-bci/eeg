import XCTest
@testable import EEGCore

final class ReferenceLiveTimestampWorkflowTests: XCTestCase {
    typealias Flow = ReferenceLiveTimestampWorkflow
    func make(transition: Double = 60) throws -> Flow {
        try Flow(configuration: .init(clock: .init(maximumCounter: 127, decimalPrecision: 6, historyCapacity: 5),
            sampleRate: 128, warmupSeconds: 0.125, maximumDeviation: 0.5,
            adaptiveTransitionSeconds: transition, hardwareOffset: 0.08, maximumPackets: 256))
    }
    func packet(_ counter: Int) -> ReferenceTimestampClock.Packet { .init(type: 16, counter: counter, interpolationFlag: 0) }
    func testWarmupBoundaryLastAnchorAndOffsetDoNotShiftInternalClock() throws {
        var flow = try make()
        XCTAssertEqual(try flow.process([packet(0)],observedTime: 100).status,.warmingUp)
        XCTAssertEqual(try flow.process([packet(1)],observedTime: 100.124).referenceErrorCode,21)
        let anchor = try flow.process([packet(2),packet(3)],observedTime: 100.125)
        XCTAssertEqual(anchor.status,.ready); XCTAssertEqual(anchor.retainedInputIndices,[1])
        XCTAssertEqual(anchor.beforeHardwareOffset,[100.125])
        XCTAssertEqual(anchor.timestamps[0],100.045,accuracy: 1e-12)
        XCTAssertEqual(flow.lastPreOffsetEEGTime,100.125)
        XCTAssertEqual(flow.clock.previousCounter,3)
        XCTAssertEqual(flow.clock.history.map(\.counter),[3])
        let next = try flow.process([packet(4)],observedTime: 100.1328125)
        XCTAssertEqual(next.beforeHardwareOffset,[100.132813])
        XCTAssertEqual(flow.clock.eegTimestamp,100.1328125)
    }
    func testLostTimeRestartsWarmupWithoutErasingDiagnosticHistory() throws {
        var flow = try make()
        _ = try flow.process([packet(0)],observedTime: 100)
        _ = try flow.process([packet(1)],observedTime: 100.125)
        let lost = try flow.process([packet(9)],observedTime: 102)
        XCTAssertEqual(lost.status,.warmingUp)
        XCTAssertTrue(flow.pendingAnchor); XCTAssertFalse(flow.ready)
        XCTAssertEqual(flow.clock.history.map(\.counter),[1])
        let restarted = try flow.process([packet(10),packet(11)],observedTime: 102.125)
        XCTAssertEqual(restarted.retainedInputIndices,[1])
        XCTAssertEqual(flow.clock.history.map(\.counter),[1,11])
        XCTAssertEqual(flow.clock.cumulativeCounterDistance,1)
    }
    func testBadCounterTimeRequestsResetAndDoesNotPublishShiftedOutput() throws {
        var flow = try make()
        _ = try flow.process([packet(0)],observedTime: 100)
        _ = try flow.process([packet(1)],observedTime: 100.125)
        let bad = try flow.process([packet(101)],observedTime: 100.13)
        XCTAssertEqual(bad.status,.timestampRejected); XCTAssertEqual(bad.referenceErrorCode,22)
        XCTAssertTrue(bad.timestamps.isEmpty)
        XCTAssertEqual(flow.lastPreOffsetEEGTime,100.125)
        XCTAssertTrue(flow.pendingOrigin); XCTAssertTrue(flow.pendingAnchor)
        // Error22 preserves mutations already made by processEeg and sync.
        XCTAssertEqual(flow.clock.previousCounter,101)
        XCTAssertEqual(flow.clock.history.map(\.counter),[1,101])
    }
    func testAdaptiveUpdateUsesPostBatchCountAndPriorRate() throws {
        var flow = try make(transition: 0.125)
        _ = try flow.process([packet(0)],observedTime: 100)
        _ = try flow.process([packet(1)],observedTime: 100.125)
        let result = try flow.process([packet(33)],observedTime: 100.4)
        XCTAssertEqual(result.beforeHardwareOffset,[100.375])
        XCTAssertEqual(flow.adaptiveRate,32 / 0.275,accuracy: 1e-10)
        XCTAssertEqual(flow.clock.eegTimestamp,100.3751,accuracy: 1e-12)
    }
    func testOldAnchorRequestsNewOriginWithoutClearingHistory() throws {
        var flow = try Flow(configuration: .init(clock: .init(maximumCounter: 127,decimalPrecision: 6,historyCapacity: 5),
            sampleRate: 128,warmupSeconds: 0,maximumDeviation: 0.5,
            adaptiveTransitionSeconds: 60,hardwareOffset: 0.08,maximumPackets: 4))
        let rejected = try flow.process([packet(1)],observedTime: 0.5)
        XCTAssertEqual(rejected.status,.anchorRejected)
        XCTAssertEqual(rejected.referenceErrorCode,21)
        XCTAssertFalse(rejected.didReanchor)
        XCTAssertTrue(flow.pendingAnchor); XCTAssertTrue(flow.pendingOrigin)
        let ready = try flow.process([packet(2)],observedTime: 2)
        XCTAssertEqual(ready.status,.ready); XCTAssertTrue(ready.didReanchor)
    }

    func testUnsupportedInputIsAtomicAndEmptyDoesNotReset() throws {
        var flow = try make()
        XCTAssertEqual(try flow.process([],observedTime: 500).status,.empty)
        XCTAssertEqual(flow.origin,-1)
        XCTAssertThrowsError(try flow.process([.init(type: 32,counter: 0,interpolationFlag: 0)],observedTime: 100))
        XCTAssertThrowsError(try flow.process([packet(0)],observedTime: .nan))
        XCTAssertEqual(flow.origin,-1); XCTAssertEqual(flow.clock.eegTimestamp,1)
    }
}
