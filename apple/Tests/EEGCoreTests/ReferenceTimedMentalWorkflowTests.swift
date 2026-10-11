import XCTest
@testable import EEGCore

/// Authored counter/measurement fixtures, not a participant or Cortex oracle.
final class ReferenceTimedMentalWorkflowTests: XCTestCase {
    typealias W = ReferenceTimedMentalWorkflow
    private var configuration: ReferenceLiveTimestampWorkflow.Configuration {
        .init(clock: .init(maximumCounter: 127, decimalPrecision: 6, historyCapacity: 16),
            sampleRate: 128, warmupSeconds: 0.125, maximumDeviation: 0.5,
            adaptiveTransitionSeconds: 60, hardwareOffset: 0.08, maximumPackets: 256)
    }
    private func mental() throws -> ReferenceResolvedMentalWorkflow {
        let profile = ReferenceRuntimeRecipe.ConvertedProfile(version: "20180327", values: [
            "cognitiv-bands": .matrix(.init(rows: 1, columns: 2, elements: [4,20])),
            "cognitiv-isBandPower": .integer(1),
            "cognitiv-winSizeInSec": .floating(0.0625),
            "cognitiv-stepSizeInSec": .floating(0.03125)])
        return try .init(profile: profile, headsetTypeID: 9, inputChannels: [92,999,54],
            settings: .init(sampleRate: 128, maximumBufferedSamples: 512, maximumSamplesPerBlock: 256,
                maximumFeatures: 100, backgroundEnabled: false, actions: [2], activationSetting: 3), runtime: nil)
    }
    private func packet(_ n: Int) -> W.Packet {
        let x = Double(n)
        return .init(clock: .init(type: 16, counter: n % 128, interpolationFlag: 0),
                     measurements: [sin(x * 0.3), cos(x * 0.2), 2 * sin(x * 0.7)])
    }
    private func make() throws -> W { try .init(configuration: configuration, mental: mental()) }

    func testWarmupLastAnchorAndAccumulationMatchManualComposition() throws {
        var flow = try make()
        XCTAssertNil(try flow.process([packet(0)], observedTime: 100, overallContactQuality: 100).mental)
        let originals = [packet(1),packet(2)]
        let anchor = try flow.process(originals, observedTime: 100.125, overallContactQuality: 100)
        XCTAssertEqual(anchor.timing.retainedInputIndices, [1])
        XCTAssertTrue(anchor.timing.didReanchor)
        XCTAssertEqual(anchor.originals.map(\.measurements), originals.map(\.measurements))
        XCTAssertEqual(anchor.mental?.inputSamples, packet(2).measurements.map { [$0] })
        XCTAssertEqual(flow.bufferedSamples, 1)
        let next = (3...9).map(packet)
        let result = try flow.process(next, observedTime: 100.125 + 7.0 / 128, overallContactQuality: 100)
        XCTAssertEqual(result.mental?.raw.status, .featuresOnly)
        var manual = try mental()
        _ = try manual.process(inputSamples: packet(2).measurements.map { [$0] }, overallContactQuality: 100)
        let matrix = (0..<3).map { row in next.map { $0.measurements[row] } }
        let expected = try manual.process(inputSamples: matrix, overallContactQuality: 100)
        XCTAssertEqual(result.mental?.raw.filteredEpoch, expected.raw.filteredEpoch)
        XCTAssertEqual(result.mental?.raw.features, expected.raw.features)
        XCTAssertNil(result.mental?.raw.command)
    }
    func testTimestampRejectionAndNewWarmupClearPendingSignalWindow() throws {
        var flow = try make()
        _ = try flow.process([packet(0)], observedTime: 100, overallContactQuality: 100)
        _ = try flow.process([packet(1)], observedTime: 100.125, overallContactQuality: 100)
        XCTAssertEqual(flow.bufferedSamples, 1)
        let bad = try flow.process([packet(101)], observedTime: 100.13, overallContactQuality: 100)
        XCTAssertEqual(bad.timing.status, .timestampRejected)
        XCTAssertNil(bad.mental); XCTAssertEqual(flow.bufferedSamples, 0)
        XCTAssertEqual(try flow.process([packet(102)], observedTime: 102, overallContactQuality: 100).timing.status, .warmingUp)
        let restarted = try flow.process([packet(103)], observedTime: 102.125, overallContactQuality: 100)
        XCTAssertTrue(restarted.timing.didReanchor)
        XCTAssertEqual(restarted.mental?.raw.status, .waiting)
        XCTAssertEqual(flow.bufferedSamples, 1)
        let gap = try flow.process([packet(104)], observedTime: 105, overallContactQuality: 100)
        XCTAssertEqual(gap.timing.status, .warmingUp)
        XCTAssertEqual(flow.bufferedSamples, 0)
    }
    func testMalformedMeasurementAndQualityFailAtomicallyWhileEmptyDoesNotDrain() throws {
        var flow = try make()
        let malformed = W.Packet(clock: packet(0).clock, measurements: [1])
        XCTAssertThrowsError(try flow.process([malformed], observedTime: 100, overallContactQuality: 100))
        XCTAssertEqual(flow.timing.origin, -1)
        XCTAssertThrowsError(try flow.process([packet(0)], observedTime: 100, overallContactQuality: .nan))
        XCTAssertEqual(flow.timing.origin, -1)
        _ = try flow.process([packet(0)], observedTime: 100, overallContactQuality: 100)
        _ = try flow.process([packet(1)], observedTime: 100.125, overallContactQuality: 100)
        let before = flow.timing.clock.previousCounter
        let empty = try flow.process([], observedTime: 110, overallContactQuality: 100)
        XCTAssertEqual(empty.timing.status, .empty); XCTAssertNil(empty.mental)
        XCTAssertEqual(flow.bufferedSamples, 1)
        XCTAssertEqual(flow.timing.clock.previousCounter, before)
    }

    func testMissingAndDuplicateCountersCannotBridgeWindowAndNextBatchRecovers() throws {
        var flow = try make()
        _ = try flow.process([packet(0)], observedTime: 100, overallContactQuality: 100)
        _ = try flow.process([packet(1)], observedTime: 100.125, overallContactQuality: 100)
        let gap = try flow.process([packet(3)], observedTime: 100.140625, overallContactQuality: 100)
        XCTAssertEqual(gap.timing.status, .ready)
        XCTAssertTrue(gap.discontinuityDetected); XCTAssertNil(gap.mental)
        XCTAssertEqual(gap.originals.count, 1); XCTAssertEqual(flow.bufferedSamples, 0)
        let recovery = try flow.process([packet(4)], observedTime: 100.1484375, overallContactQuality: 100)
        XCTAssertFalse(recovery.discontinuityDetected); XCTAssertEqual(flow.bufferedSamples, 1)
        let duplicate = try flow.process([packet(4)], observedTime: 100.1484375, overallContactQuality: 100)
        XCTAssertTrue(duplicate.discontinuityDetected); XCTAssertNil(duplicate.mental)
        XCTAssertEqual(flow.bufferedSamples, 0)
        // An INTERNAL gap rejects every sample in the batch, including its prefix.
        let internalGap = try flow.process([packet(5), packet(7)], observedTime: 100.171875, overallContactQuality: 100)
        XCTAssertTrue(internalGap.discontinuityDetected); XCTAssertEqual(flow.bufferedSamples, 0)
        let contiguous = (8...15).map(packet)
        let accepted = try flow.process(contiguous, observedTime: 100.234375, overallContactQuality: 100)
        XCTAssertFalse(accepted.discontinuityDetected)
        XCTAssertEqual(accepted.mental?.raw.status, .featuresOnly)
    }

    func testContiguousWrapAndExplicitInterpolatedRowsRemainAdmissible() throws {
        var flow = try make()
        _ = try flow.process([packet(125)], observedTime: 100, overallContactQuality: 100)
        _ = try flow.process([packet(126)], observedTime: 100.125, overallContactQuality: 100)
        let generated = W.Packet(clock: .init(type: 16, counter: 127, interpolationFlag: 1),
                                 measurements: packet(127).measurements)
        let result = try flow.process([generated,packet(128)], observedTime: 100.140625,
                                      overallContactQuality: 100)
        XCTAssertFalse(result.discontinuityDetected)
        XCTAssertEqual(flow.bufferedSamples, 3)
        XCTAssertEqual(result.originals[0].clock.interpolationFlag, 1)
    }
}
