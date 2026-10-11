import XCTest
@testable import EEGCore

final class ReferenceOfflineTimestampWorkflowTests: XCTestCase {
    private let config = ReferenceTimestampClock.Configuration(maximumCounter: 127, decimalPrecision: 6, historyCapacity: 5)
    private func packet(_ n: Int, _ flag: Int = 0) -> ReferenceTimestampClock.Packet {
        .init(type: 16, counter: n, interpolationFlag: flag)
    }
    func testOfflineAnchorsFirstAndRetainsRestWithoutHardwareOffset() throws {
        var flow = try ReferenceOfflineTimestampWorkflow(configuration: config, sampleRate: 128,
            startTime: 100, lastPreOffsetEEGTime: 1)
        let result = try flow.process([packet(126),packet(127,1),packet(0)], maximumPackets: 3)
        XCTAssertEqual(result.retainedInputIndices, [0,1,2])
        XCTAssertTrue(result.discardedInputIndices.isEmpty)
        XCTAssertEqual(result.timestamps, [100,100.007813,100.015625])
        XCTAssertEqual(flow.clock?.history.map(\.counter), [0])
        XCTAssertEqual(flow.clock?.cumulativeCounterDistance, 3)
        let later = try flow.process([packet(1)], maximumPackets: 1)
        XCTAssertEqual(later.timestamps, [100.023438])
    }
    func testPartitioningDoesNotReanchorAndEmptyEstablishedBatchIsHarmless() throws {
        var whole = try ReferenceOfflineTimestampWorkflow(configuration: config, sampleRate: 128,
            startTime: 400, lastPreOffsetEEGTime: 1)
        var split = whole
        let packets = (0..<80).map { packet($0) }
        let a = try whole.process(packets, maximumPackets: 80).timestamps
        var b = try split.process(Array(packets.prefix(11)), maximumPackets: 80).timestamps
        XCTAssertTrue(try split.process([], maximumPackets: 80).timestamps.isEmpty)
        b += try split.process(Array(packets.dropFirst(11)), maximumPackets: 80).timestamps
        XCTAssertEqual(a,b)
        XCTAssertEqual(whole.clock?.history,split.clock?.history)
    }
    func testRejectsUnsupportedPacketsAndInvalidAnchorWithoutPublishingState() throws {
        var flow = try ReferenceOfflineTimestampWorkflow(configuration: config, sampleRate: 128,
            startTime: 100, lastPreOffsetEEGTime: 100)
        XCTAssertThrowsError(try flow.process([packet(0)], maximumPackets: 1))
        XCTAssertNil(flow.clock)
        XCTAssertThrowsError(try flow.process([], maximumPackets: 1))
        var valid = try ReferenceOfflineTimestampWorkflow(configuration: config, sampleRate: 128,
            startTime: 100, lastPreOffsetEEGTime: 1)
        XCTAssertThrowsError(try valid.process([packet(0),.init(type: 32,counter: 1,interpolationFlag: 0)], maximumPackets: 2))
        XCTAssertNil(valid.clock)
        XCTAssertThrowsError(try valid.process([packet(128)], maximumPackets: 1))
    }
    func testMotionOwnAnchorCounterWrapAndUnroundedAccumulation() throws {
        var motion = try ReferenceOrdinaryMotionClock(maximumCounter: 127, decimalPrecision: 6)
        XCTAssertEqual(try motion.process(counter: 127,sampleRate: 3,firstAnchorTime: 100),100)
        XCTAssertEqual(try motion.process(counter: 0,sampleRate: 3,firstAnchorTime: 999),100.333333)
        XCTAssertEqual(try motion.process(counter: 1,sampleRate: 3,firstAnchorTime: 999),100.666667)
        XCTAssertEqual(try motion.process(counter: 2,sampleRate: 3,firstAnchorTime: 999),101)
        XCTAssertEqual(try motion.process(counter: 2,sampleRate: 3,firstAnchorTime: 999),101)
        XCTAssertThrowsError(try motion.process(counter: 3,sampleRate: 0,firstAnchorTime: 999))
        XCTAssertEqual(motion.previousCounter,2)
    }
    func testResetGateStrictBoundaryFirstEEGViolationAndPreservedInput() throws {
        let packets = [ReferenceTimestampClock.TimedPacket(type: 32, timestamp: 0),
            .init(type: 16, timestamp: 99.5), .init(type: 16, timestamp: 100.5),
            .init(type: 16, timestamp: 99.49), .init(type: 16, timestamp: 101)]
        let result = try ReferenceTimestampResetGate.evaluate(packets, currentTime: 100,
            maximumDeviation: 0.5, maximumPackets: 5)
        XCTAssertEqual(result.firstInvalidIndex,3)
        XCTAssertEqual(result.referenceErrorCode,22)
        XCTAssertEqual(packets[3].timestamp,99.49)
        let clean = try ReferenceTimestampResetGate.evaluate(Array(packets.prefix(3)),currentTime: 100,
            maximumDeviation: 0.5,maximumPackets: 5)
        XCTAssertFalse(clean.requiresReanchor)
        XCTAssertEqual(clean.referenceErrorCode,0)
        XCTAssertThrowsError(try ReferenceTimestampResetGate.evaluate(packets,currentTime: .nan,
            maximumDeviation: 0.5,maximumPackets: 5))
    }

}
