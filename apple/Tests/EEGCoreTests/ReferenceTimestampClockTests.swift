import XCTest
@testable import EEGCore

final class ReferenceTimestampClockTests: XCTestCase {
    typealias C = ReferenceTimestampClock
    private let config = C.Configuration(maximumCounter: 127, decimalPrecision: 2, historyCapacity: 2)
    func testRoundingTiesAwayAndExplicitPrecision() throws {
        XCTAssertEqual(try C.round(1.25, decimalPrecision: 1), 1.3)
        XCTAssertEqual(try C.round(-1.25, decimalPrecision: 1), -1.3)
        XCTAssertEqual(try C.round(123.125, decimalPrecision: 3), 123.125)
        XCTAssertThrowsError(try C.round(1, decimalPrecision: 10))
        XCTAssertThrowsError(try C.round(.greatestFiniteMagnitude, decimalPrecision: 9))
    }
    func testLastEEGAnchorAndExplicitUnsupportedReset() throws {
        let packets = [C.Packet(type: 16,counter: 2,interpolationFlag: 0),
                       .init(type: 32,counter: 4,interpolationFlag: 0),
                       .init(type: 16,counter: 7,interpolationFlag: 0),
                       .init(type: 32,counter: 5,interpolationFlag: 0)]
        let result = try C.anchor(packets: packets, suppliedTime: 1.125, lastDataTimestamp: -1,
                                  motionTimestamp: -1, configuration: config, maximumPackets: 4)
        XCTAssertEqual(result.retainedIndex, 2); XCTAssertEqual(result.timestamp, 1.13)
        XCTAssertEqual(result.clock.previousCounter, 7)
        XCTAssertEqual(result.clock.eegTimestamp, 1.125)
        XCTAssertEqual(result.clock.cumulativeCounterDistance, 1)
        XCTAssertTrue(result.clock.history.isEmpty)
        XCTAssertThrowsError(try C.anchor(packets: packets, suppliedTime: 1, lastDataTimestamp: 1,
            motionTimestamp: -1, configuration: config, maximumPackets: 4))
        XCTAssertThrowsError(try C.anchor(packets: [], suppliedTime: 1, lastDataTimestamp: -1,
            motionTimestamp: -1, configuration: config, maximumPackets: 4))
    }
    func testModuloRetainsUnroundedStateAndMarksHistory() throws {
        var clock = try C(configuration: config, previousCounter: 127, eegTimestamp: 1.0001,
                          motionTimestamp: 0, cumulativeCounterDistance: 1)
        let a = try clock.process(.init(type: 16,counter: 0,interpolationFlag: 1), sampleRate: 16)
        let b = try clock.process(.init(type: 16,counter: 1,interpolationFlag: 0), sampleRate: 16)
        XCTAssertEqual(a.timestamp, 1.06); XCTAssertEqual(b.timestamp, 1.13)
        XCTAssertFalse(a.insertedIntoHistory); XCTAssertTrue(b.insertedIntoHistory)
        XCTAssertEqual(clock.history.count, 1)
        XCTAssertEqual(clock.cumulativeCounterDistance, 3)
        let duplicate = try clock.process(.init(type: 16,counter: 1,interpolationFlag: 0), sampleRate: 16)
        XCTAssertEqual(duplicate.counterDistance, 0)
        _ = try clock.process(.init(type: 16,counter: 2,interpolationFlag: 0), sampleRate: 16)
        XCTAssertEqual(clock.history.map(\.counter), [1,2])
    }
    func testSynchronizationStrictThresholdAndDirectionCounters() throws {
        var clock = try C(configuration: config, previousCounter: 0, eegTimestamp: 1,
                          motionTimestamp: -1, cumulativeCounterDistance: 1)
        let up = try clock.synchronize(realTime: 2, headsetMode: 7, configuredMotionRate: 32)
        XCTAssertTrue(up.motionTimestampWasNegative)
        XCTAssertEqual(up.correction, 0.0001)
        XCTAssertEqual(clock.eegTimestamp, 1.0001)
        XCTAssertEqual(clock.motionTimestamp, -0.9999)
        _ = try clock.synchronize(realTime: 2, headsetMode: 7, configuredMotionRate: 32)
        XCTAssertEqual(clock.consecutivePositiveCorrections, 2)
        let down = try clock.synchronize(realTime: 0, headsetMode: 7, configuredMotionRate: 0)
        XCTAssertEqual(down.correction, -0.0001)
        XCTAssertEqual(clock.consecutivePositiveCorrections, 0)
        XCTAssertEqual(clock.consecutiveNegativeCorrections, 1)
        XCTAssertEqual(clock.motionTimestamp, 0)
        var boundary = try C(configuration: config, previousCounter: 0, eegTimestamp: 0,
                             motionTimestamp: 0, cumulativeCounterDistance: 0)
        XCTAssertEqual(try boundary.synchronize(realTime: 0.00005, headsetMode: 1, configuredMotionRate: 1).correction, 0)
        boundary = try C(configuration: config, previousCounter: 0, eegTimestamp: 0.00005,
                         motionTimestamp: 0, cumulativeCounterDistance: 0)
        XCTAssertEqual(try boundary.synchronize(realTime: 0, headsetMode: 1, configuredMotionRate: 1).correction, 0)
    }
    func testAdaptiveRateTransitionUsesPreviousRatesThenUpdates() throws {
        let nominal = C.Rates(eeg: 128, motion: 32)
        let adaptive = C.Rates(eeg: 127.9, motion: 31.975)
        let boundary = try C.rateDecision(elapsedSinceAnchor: 60, transitionSeconds: 60,
            forceNominalRates: false, nominal: nominal, adaptive: adaptive,
            cumulativeCounterDistance: 7681, configuredEEGRate: 128, configuredMotionRate: 32, headsetMode: 7)
        XCTAssertTrue(boundary.usedNominalRates); XCTAssertNil(boundary.adaptiveRatesForNextBatch)
        let after = try C.rateDecision(elapsedSinceAnchor: 64, transitionSeconds: 60,
            forceNominalRates: false, nominal: nominal, adaptive: adaptive,
            cumulativeCounterDistance: 8193, configuredEEGRate: 128, configuredMotionRate: 32, headsetMode: 7)
        XCTAssertEqual(after.ratesForCurrentBatch, adaptive)
        XCTAssertEqual(after.adaptiveRatesForNextBatch, nominal)
        let mode9 = try C.rateDecision(elapsedSinceAnchor: 64, transitionSeconds: 60,
            forceNominalRates: false, nominal: nominal, adaptive: adaptive,
            cumulativeCounterDistance: 8193, configuredEEGRate: 128, configuredMotionRate: 32, headsetMode: 9)
        XCTAssertEqual(mode9.adaptiveRatesForNextBatch?.motion, 6.4)
        let forced = try C.rateDecision(elapsedSinceAnchor: 64, transitionSeconds: 60,
            forceNominalRates: true, nominal: nominal, adaptive: adaptive,
            cumulativeCounterDistance: 8193, configuredEEGRate: 128, configuredMotionRate: 32, headsetMode: 7)
        XCTAssertTrue(forced.usedNominalRates); XCTAssertNil(forced.adaptiveRatesForNextBatch)
        XCTAssertThrowsError(try C.rateDecision(elapsedSinceAnchor: 64, transitionSeconds: 60,
            forceNominalRates: false, nominal: nominal, adaptive: adaptive,
            cumulativeCounterDistance: 0, configuredEEGRate: 128, configuredMotionRate: 32, headsetMode: 7))
    }
    func testHardwareOffsetRetainsMeasuredTimestampAndLastPreOffsetEEG() throws {
        let packets = [C.TimedPacket(type: 16, timestamp: 10), .init(type: 16, timestamp: 10.5),
                       .init(type: 32, timestamp: 10.75)]
        let result = try C.hardwareTiming(packets: packets, offset: 0.08, maximumPackets: 3)
        XCTAssertEqual(result.beforeCorrection, packets)
        XCTAssertEqual(result.afterCorrection.map(\.timestamp), [9.92,10.42,10.67])
        XCTAssertEqual(result.lastEEGBeforeCorrection, 10.5)
        XCTAssertEqual(result.subtractedOffset, 0.08)
        XCTAssertNil(try C.hardwareTiming(packets: [.init(type: 32,timestamp: 1)], offset: 0.08, maximumPackets: 1).lastEEGBeforeCorrection)
        XCTAssertThrowsError(try C.hardwareTiming(packets: packets, offset: .infinity, maximumPackets: 3))
    }
    func testInvalidInputDoesNotAdvanceState() throws {
        var clock = try C(configuration: config, previousCounter: 0, eegTimestamp: 1,
                          motionTimestamp: 0, cumulativeCounterDistance: UInt32.max)
        XCTAssertThrowsError(try clock.process(.init(type: 16,counter: 1,interpolationFlag: 0), sampleRate: 128))
        XCTAssertEqual(clock.previousCounter, 0); XCTAssertEqual(clock.eegTimestamp, 1)
        XCTAssertTrue(clock.history.isEmpty)
        XCTAssertThrowsError(try clock.process(.init(type: 16,counter: 1,interpolationFlag: 0), sampleRate: 0))
        XCTAssertThrowsError(try clock.process(.init(type: 32,counter: 1,interpolationFlag: 0), sampleRate: 128))
        XCTAssertThrowsError(try clock.synchronize(realTime: .nan, headsetMode: 7, configuredMotionRate: 32))
        XCTAssertEqual(clock.eegTimestamp, 1)
    }
}
