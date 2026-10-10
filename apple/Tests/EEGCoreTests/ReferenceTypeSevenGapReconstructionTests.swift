import XCTest
@testable import EEGCore

final class ReferenceTypeSevenGapReconstructionTests: XCTestCase {
    typealias G = ReferenceTypeSevenGapReconstruction
    func sample(_ counter: Int, _ eeg: Double, _ cq: Double) -> G.Sample {
        .init(counter: counter, values: [eeg, eeg, eeg, eeg, eeg, eeg, eeg, cq])
    }
    func testHistoricalCQOverridesInterpolationButMeasurementsRemainUntouched() throws {
        var state = try G(maximumCounter: 127)
        // An adjacent pair stores a real observation without creating samples.
        XCTAssertEqual(try state.reconstruct(previous: sample(0, 0, 1),
            current: sample(1, 0, 37)).inserted, [])
        let previous = sample(127, 0, 100)
        let current = sample(2, 9, 400)
        let result = try state.reconstruct(previous: previous, current: current)
        XCTAssertEqual(result.inserted?.map(\.counter), [0, 1])
        XCTAssertEqual(result.inserted?.map { $0.values[0] }, [3, 6])
        XCTAssertEqual(result.inserted?.map { $0.values[7] }, [0, 37])
        XCTAssertEqual(result.measuredCurrent, current)
        XCTAssertEqual(previous.values[7], 100)
        XCTAssertEqual(state.rawCQCache[2], 400)
    }
    func testCurrentCQIsStoredBeforeRepeatedSlotInMaximumAdmittedGap() throws {
        var state = try G(maximumCounter: 127)
        let result = try state.reconstruct(previous: sample(0, 0, 0), current: sample(65, 65, 93))
        XCTAssertEqual(result.inserted?.count, 64)
        // counter1 has same CQ ordinal as current65. This is look-ahead cache
        // replacement from the body, not a causal interpolation estimate.
        XCTAssertEqual(result.inserted?.first?.values[7], 93)
        XCTAssertEqual(result.inserted?[13].counter, 14)
        XCTAssertEqual(try XCTUnwrap(result.inserted)[13].values[7], 14 * 93.0 / 65, accuracy: 1e-12)
        XCTAssertEqual(result.inserted?.last?.counter, 64)
        XCTAssertEqual(result.inserted?.last?.values[7], 0)
    }
    func testRejectedDistancesLeaveCacheUnchanged() throws {
        var state = try G(maximumCounter: 127)
        XCTAssertNil(try state.reconstruct(previous: sample(1, 1, 1), current: sample(1, 2, 90)).inserted)
        XCTAssertNil(try state.reconstruct(previous: sample(0, 1, 1), current: sample(66, 2, 90)).inserted)
        XCTAssertEqual(state.rawCQCache, Array(repeating: 0, count: 14))
        XCTAssertEqual(try state.reconstruct(previous: sample(127, 1, 1), current: sample(0, 2, 90)).inserted, [])
        XCTAssertEqual(state.rawCQCache[0], 90)
    }
    func testInvalidAndOverflowingValuesDoNotPartiallyUpdateCache() throws {
        var state = try G(maximumCounter: 127)
        XCTAssertThrowsError(try state.reconstruct(previous: sample(0, .nan, 0), current: sample(2, 2, 40)))
        XCTAssertThrowsError(try state.reconstruct(previous: sample(0, -.greatestFiniteMagnitude, 0),
            current: sample(2, .greatestFiniteMagnitude, 40)))
        XCTAssertEqual(state.rawCQCache, Array(repeating: 0, count: 14))
        XCTAssertThrowsError(try state.reconstruct(previous: sample(-1, 0, 0), current: sample(2, 2, 40)))
    }
    func testProcessingClockResetIsStrictAndRetainsCQCache() throws {
        var state = try G(maximumCounter: 127)
        _ = try state.processEEG([sample(0, 0, 10), sample(1, 1, 37)], callTime: 10, maximumPackets: 2)
        let atBoundary = try state.processEEG([sample(3, 3, 39)], callTime: 10.5, maximumPackets: 1)
        XCTAssertEqual(atBoundary.map { $0.sample.counter }, [2, 3])
        XCTAssertEqual(atBoundary.map(\.isInterpolated), [true, false])
        let beyond = try state.processEEG([sample(70, 70, 99)], callTime: 11.001, maximumPackets: 1)
        XCTAssertEqual(beyond.map { $0.sample.counter }, [70])
        XCTAssertEqual(state.rawCQCache[1], 37)
        XCTAssertEqual(state.rawCQCache[3], 39)
        // First package after reset bypasses interpolate/storeLastRawCQ.
        XCTAssertEqual(state.rawCQCache[6], 0)
    }
    func testRejectedPacketDoesNotMoveHistoryAndBatchFailureIsAtomic() throws {
        var state = try G(maximumCounter: 127)
        _ = try state.processEEG([sample(0, 0, 0)], callTime: 10, maximumPackets: 1)
        let output = try state.processEEG([sample(66, 66, 66), sample(2, 2, 90)], callTime: 10.1, maximumPackets: 2)
        XCTAssertEqual(output.map { $0.sample.counter }, [1, 2])
        XCTAssertEqual(state.previousMeasured?.counter, 2)
        XCTAssertEqual(state.lastSuccessfulCallTime, 10.1)
        let before = state.rawCQCache
        XCTAssertThrowsError(try state.processEEG([sample(3, 3, 33), sample(4, .nan, 44)],
            callTime: 10.2, maximumPackets: 2))
        XCTAssertEqual(state.rawCQCache, before)
        XCTAssertEqual(state.previousMeasured?.counter, 2)
        XCTAssertEqual(state.lastSuccessfulCallTime, 10.1)
        XCTAssertEqual(try state.processEEG([], callTime: 15, maximumPackets: 1), [])
        XCTAssertEqual(state.previousMeasured?.counter, 2)
    }
    func testSameClockBatchPartitionPreservesReconstructionAndProvenance() throws {
        var whole = try G(maximumCounter: 127)
        var parts = try G(maximumCounter: 127)
        let samples = [sample(126, 0, 10), sample(2, 4, 20), sample(5, 7, 30)]
        let expected = try whole.processEEG(samples, callTime: 10, maximumPackets: 3)
        var actual: [G.Emitted] = []
        for sample in samples { actual += try parts.processEEG([sample], callTime: 10, maximumPackets: 1) }
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(actual.filter { !$0.isInterpolated }.map(\.sample), samples)
        XCTAssertEqual(parts.rawCQCache, whole.rawCQCache)
    }
    func testGapClockSearchCompositionFeedsDiagnosticWithoutDispatch() throws {
        // Explicit test fixture clock/rate/precision. Does not infer deployed
        // startup flags or the hardware processing-stage order.
        let retained = (0..<160).filter { !(25...28).contains($0) && !(100...102).contains($0) }
        let measurements = retained.map { i -> G.Sample in
            .init(counter: i % 128, values: [sin(Double(i) * 0.4), cos(Double(i) * 0.25),
                                             0, 0, 0, 0, 0, Double(i)])
        }
        var gap = try G(maximumCounter: 127)
        let emitted = try gap.processEEG(measurements, callTime: 10, maximumPackets: 160)
        XCTAssertEqual(emitted.count, 160)
        XCTAssertEqual(emitted.filter { !$0.isInterpolated }.map(\.sample), measurements)
        XCTAssertEqual(emitted.filter(\.isInterpolated).count, 7)
        var clock = try ReferenceTimestampClock(configuration: .init(maximumCounter: 127,
            decimalPrecision: 9, historyCapacity: 256), previousCounter: 127,
            eegTimestamp: 10 - 1.0 / 128, motionTimestamp: 0, cumulativeCounterDistance: 0)
        let stamped = try emitted.map { entry in
            try clock.process(.init(type: 16, counter: entry.sample.counter,
                                    interpolationFlag: entry.isInterpolated ? 1 : 0), sampleRate: 128)
        }
        XCTAssertEqual(clock.history.count, measurements.count)
        XCTAssertEqual(stamped.last?.unroundedTimestamp, 10 + 159.0 / 128)
        let buffer = try ReferenceTimestampSearch(startIndex: 0, timestamps: stamped.map(\.timestamp), maximumSamples: 160)
        let slice = try buffer.search(cursor: 0, from: stamped[0].timestamp, through: stamped[127].timestamp)
        XCTAssertEqual(slice.count, 128)
        let recipe = ReferenceRawMentalWorkflow.Recipe(sampleRate: 128, selectedChannelCount: 2,
            windowSeconds: 1, stepSeconds: 0.125, maximumBufferedSamples: 256, maximumSamplesPerBlock: 160,
            bands: [.init(lowerHz: 4, upperHz: 7)], features: [.power(.init(row: 0, band: 0))],
            backgroundEnabled: false, actions: [2], activationSetting: 3)
        var diagnostic = try ReferenceRawMentalWorkflow(recipe: recipe, runtime: nil)
        let rows = (0..<2).map { channel in emitted.prefix(slice.count).map { $0.sample.values[channel] } }
        // Explicit authored quality100 is not derived from cache zeros or from
        // unqualified physical contacts. No learned model is manufactured.
        let result = try diagnostic.process(selectedChannelSamples: rows, overallContactQuality: 100)
        XCTAssertEqual(result.status, .featuresOnly)
        XCTAssertFalse(try XCTUnwrap(result.bandPowers).isEmpty)
        XCTAssertNil(result.command)
    }
}
