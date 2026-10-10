import XCTest
@testable import EEGCore

final class ReferenceContactQualityRoutingTests: XCTestCase {
    private func recipe() throws -> ReferenceTypeSevenCQRecipe.Recipe {
        try ReferenceTypeSevenCQRecipe.current(revision: 0x0740, configurationBytes: [1,128,0,16,32,16], connectionType: 1)
    }
    func testCounterRoutingAndPacketGateBoundaries() throws {
        XCTAssertEqual(try ReferenceContactQualityRouting.ordinal(counter: 0), 0)
        XCTAssertEqual(try ReferenceContactQualityRouting.ordinal(counter: 13), 13)
        XCTAssertNil(try ReferenceContactQualityRouting.ordinal(counter: 14))
        XCTAssertNil(try ReferenceContactQualityRouting.ordinal(counter: 63))
        XCTAssertEqual(try ReferenceContactQualityRouting.ordinal(counter: 64), 0)
        XCTAssertEqual(try ReferenceContactQualityRouting.ordinal(counter: 128), 0)
        XCTAssertThrowsError(try ReferenceContactQualityRouting.ordinal(counter: -1))
        XCTAssertFalse(ReferenceContactQualityRouting.passesPacketGate(packetType: 15, counter: 0, mode: 7))
        for mode in [1,3] {
            XCTAssertFalse(ReferenceContactQualityRouting.passesPacketGate(packetType: 16, counter: 128, mode: mode))
            XCTAssertTrue(ReferenceContactQualityRouting.passesPacketGate(packetType: 16, counter: 127, mode: mode))
        }
        XCTAssertTrue(ReferenceContactQualityRouting.passesPacketGate(packetType: 16, counter: 128, mode: 7))
    }
    func testAllRowsUseFinalBatchMapAndRememberSlotsWithoutRepeatedScale() throws {
        let recipe = try recipe()
        var routing = try ReferenceContactQualityRouting(recipe: recipe, maximumPackets: 32)
        let high = Double(recipe.channels[0].configuration.divisor) * 8
        let low = Double(recipe.channels[0].configuration.divisor) * 0.4
        let output = try routing.process([
            .init(packetType: 16, counter: 0, rawCQ: high, timestamp: 1),
            .init(packetType: 16, counter: 64, rawCQ: low, timestamp: 2)])
        XCTAssertEqual(output.changedOrdinals, [0,0])
        XCTAssertEqual(output.stateRows.map { $0[0] }, [0,0])
        XCTAssertEqual(output.timestamps, [1,2])
        XCTAssertEqual(routing.originalRaw[0], low)
        XCTAssertEqual(routing.rememberedMapped[0], low * 0.25)
        let next = try routing.process([.init(packetType: 16, counter: 14, rawCQ: nil, timestamp: 3)])
        XCTAssertEqual(next.changedOrdinals, [])
        XCTAssertEqual(routing.rememberedMapped[0], low * 0.25)
        XCTAssertEqual(next.diagnostics.channels[0].raw, low)
    }
    func testComposedFourteenSlotAndDetectionAdapter() throws {
        let recipe = try recipe()
        var routing = try ReferenceContactQualityRouting(recipe: recipe, maximumPackets: 32)
        let packets = recipe.channels.enumerated().map { slot, channel in
            ReferenceContactQualityRouting.Packet(packetType: 16, counter: Int32(slot),
                rawCQ: Double(channel.configuration.divisor) * 8, timestamp: Double(slot))
        }
        let batch = try routing.process(packets)
        XCTAssertEqual(batch.changedOrdinals, Array(0..<14))
        XCTAssertTrue(batch.stateRows.allSatisfy { $0 == Array(repeating: 4, count: 14) })
        XCTAssertEqual(batch.overallRows, Array(repeating: 100, count: 14))
        // Explicit adapter channel schema; no unverified vendor label-order assumptions.
        let ids = [152] + recipe.channels.map { $0.calibrationChannelID } + [147]
        let rows = batch.stateRows.indices.map { [batch.timestamps[$0]] + batch.stateRows[$0].map(Double.init) + [batch.overallRows[$0]] }
        let detection = try ReferenceContactQualityRouting.detection(rows: rows, channelIDs: ids, maximumRows: 32)
        XCTAssertEqual(detection.overall, 100)
        XCTAssertEqual(detection.timestamp, 13)
        XCTAssertEqual(detection.minimum, 4)
        XCTAssertEqual(detection.lastStates.count, 14)
    }
    func testDetectionKeepsEpochMinimumSeparateFromLastRowAndSkipsSpecialIDs() throws {
        let result = try ReferenceContactQualityRouting.detection(
            rows: [[1.9,25,1,900], [4,100,2,-123]], channelIDs: [45,147,152,163], maximumRows: 3)
        XCTAssertEqual(result.lastStates, [45:4])
        XCTAssertEqual(result.epochMinimumStates[45], 1)
        XCTAssertEqual(result.epochMinimumStates[163], 4)
        XCTAssertEqual(result.minimum, 1)
        XCTAssertEqual(result.overall, 100)
        XCTAssertEqual(result.timestamp, 2)
        let empty = try ReferenceContactQualityRouting.detection(rows: [], channelIDs: [45], maximumRows: 3)
        XCTAssertEqual(empty.minimum, 0)
        XCTAssertEqual(empty.lastStates.count, 0)
    }
    func testBoundsAndFailureDoNotCreateFakeDataOrMutateRememberedValues() throws {
        var routing = try ReferenceContactQualityRouting(recipe: recipe(), maximumPackets: 1)
        XCTAssertThrowsError(try routing.process([.init(packetType: 16, counter: 0, rawCQ: nil, timestamp: 1)]))
        XCTAssertEqual(routing.originalRaw, Array(repeating: 0, count: 14))
        XCTAssertThrowsError(try routing.process([
            .init(packetType: 16, counter: 0, rawCQ: 100, timestamp: 1),
            .init(packetType: 16, counter: 1, rawCQ: 200, timestamp: 2)]))
        XCTAssertThrowsError(try ReferenceContactQualityRouting.detection(rows: [[5]], channelIDs: [45], maximumRows: 1))
        XCTAssertThrowsError(try ReferenceContactQualityRouting.detection(rows: [[1,2]], channelIDs: [45,45], maximumRows: 1))
    }
}
