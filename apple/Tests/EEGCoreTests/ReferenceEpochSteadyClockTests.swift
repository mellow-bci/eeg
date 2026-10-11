import XCTest
@testable import EEGCore
final class ReferenceEpochSteadyClockTests: XCTestCase {
    func testExplicitUnitsQuantizationAndPositiveOverride() throws {
        let clock = try ReferenceEpochSteadyClock(systemMicroseconds: 100_000_000,steadyNanoseconds: 5_000_000_000)
        XCTAssertEqual(try clock.observation(suppliedTime: 0,currentSteadyNanoseconds: 5_125_000_999),100.125)
        XCTAssertEqual(try clock.observation(suppliedTime: -1,currentSteadyNanoseconds: 5_125_000_000),100.125)
        XCTAssertEqual(try clock.observation(suppliedTime: 103,currentSteadyNanoseconds: 0),103)
        XCTAssertThrowsError(try clock.observation(suppliedTime: .nan,currentSteadyNanoseconds: 0))
    }
    func testClockConversionFeedsLiveWarmupWithoutWallClockReads() throws {
        let clock = try ReferenceEpochSteadyClock(systemMicroseconds: 100_000_000,steadyNanoseconds: 0)
        var flow = try ReferenceLiveTimestampWorkflow(configuration: .init(
            clock: .init(maximumCounter: 127,decimalPrecision: 6,historyCapacity: 5),
            sampleRate: 128,warmupSeconds: 0.125,maximumDeviation: 0.5,
            adaptiveTransitionSeconds: 60,hardwareOffset: 0.08,maximumPackets: 4))
        let packets = [ReferenceTimestampClock.Packet(type: 16,counter: 0,interpolationFlag: 0)]
        XCTAssertEqual(try flow.process(packets,observedTime: clock.observation(suppliedTime: 0,currentSteadyNanoseconds: 0)).status,.warmingUp)
        XCTAssertEqual(try flow.process(packets,observedTime: clock.observation(suppliedTime: 0,currentSteadyNanoseconds: 125_000_000)).status,.ready)
    }
}
