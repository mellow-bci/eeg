import XCTest
@testable import EEGCore

final class ReferenceTimestampSearchTests: XCTestCase {
    typealias T = ReferenceTimestampSearch
    func buffer(_ values: [Double], start: Int64 = 0) throws -> T {
        try T(startIndex: start, timestamps: values, maximumSamples: 1024)
    }
    func testCompleteCoverageInclusivityAndEmptyGap() throws {
        let b = try buffer([1, 2, 4, 5], start: 10)
        XCTAssertEqual(try b.search(cursor: 0, from: 2, through: 4), .init(complete: true, start: 11, count: 2))
        XCTAssertEqual(try b.search(cursor: 0, from: 2.5, through: 3), .init(complete: true, start: 12, count: 0))
        XCTAssertEqual(try b.search(cursor: 0, from: 4, through: 6), .init(complete: false, start: 0, count: 0))
        XCTAssertEqual(try b.search(cursor: 12, from: 1, through: 5), .init(complete: true, start: 12, count: 2))
        XCTAssertFalse(try b.search(cursor: 14, from: 1, through: 5).complete)
    }
    func testFallbackClipsWithoutFillingMissingMeasurements() throws {
        let b = try buffer([2, 4, 5], start: 30)
        XCTAssertEqual(try b.clipped(from: 1, through: 6), .init(complete: false, start: 30, count: 3))
        XCTAssertEqual(try b.clipped(from: 3, through: 4), .init(complete: false, start: 31, count: 1))
        XCTAssertEqual(try b.clipped(from: 2.5, through: 3).count, 0)
        XCTAssertEqual(try b.clipped(from: 6, through: 7).count, 0)
    }
    func testCrossStreamFailureFallbackAndStartCache() throws {
        var r = ReferenceTimestampRouting()
        let buffers = [10: try buffer([1,2,3,4]), 20: try buffer([1,2,3]), 30: try buffer([1,2,3,4])]
        XCTAssertNil(try r.route(primaryStream: 10, streamOrder: [10,30,20], buffers: buffers,
                                 from: 2, through: 4, permissive: false))
        XCTAssertTrue(r.cachedStarts.isEmpty)
        let result = try XCTUnwrap(r.route(primaryStream: 10, streamOrder: [10,30,20], buffers: buffers,
                                          from: 2, through: 4, permissive: true))
        XCTAssertEqual(result.map(\.stream), [30,20])
        XCTAssertEqual(result.map(\.usedClippedFallback), [false,true])
        XCTAssertEqual(result.map { $0.search.count }, [3,2])
        XCTAssertEqual(r.cachedStarts, [30: 1])
    }
    func testRealTimestampSearchFeedsSubscriptionScheduling() throws {
        let primary = try buffer((0..<48).map { 1 + Double($0)/128 })
        let secondary = try buffer((0..<48).map { 1 + Double($0)/128 })
        var route = ReferenceTimestampRouting()
        var scheduler = try ReferenceSubscriptionCadence(sampleRate: 128, windowSeconds: 0.125,
                                                          stepSeconds: 0.125, startIndex: 0)
        let reads = try scheduler.process(startIndex: 0, endIndex: 48, isAlmostFull: false, maximumReads: 3) { req in
            let selected = try route.route(primaryStream: 10, streamOrder: [10,20], buffers: [10: primary,20: secondary],
                from: primary.timestamp(at: req.start), through: primary.timestamp(at: req.endExclusive-1),
                permissive: req.mayClipSearch)
            XCTAssertEqual(selected?.first?.search.count, 16)
            return selected != nil
        }
        XCTAssertEqual(reads.map(\.start), [0,16,32]); XCTAssertEqual(route.cachedStarts, [20: 32])
    }
    func testTimestampSelectedBlocksMatchDirectRawDiagnosticFeatures() throws {
        let t = try buffer((0..<160).map { 10 + Double($0)/128 })
        let rows = [(0..<160).map { sin(Double($0) * 0.4) },
                    (0..<160).map { cos(Double($0) * 0.25) }]
        let recipe = ReferenceRawMentalWorkflow.Recipe(sampleRate: 128, selectedChannelCount: 2,
            windowSeconds: 1, stepSeconds: 0.125, maximumBufferedSamples: 256, maximumSamplesPerBlock: 160,
            bands: [.init(lowerHz: 4, upperHz: 7)], features: [.power(.init(row: 0, band: 0))],
            backgroundEnabled: false, actions: [2], activationSetting: 3)
        var routed = try ReferenceRawMentalWorkflow(recipe: recipe, runtime: nil)
        var direct = try ReferenceRawMentalWorkflow(recipe: recipe, runtime: nil)
        var scheduler = try ReferenceSubscriptionCadence(sampleRate: 128, windowSeconds: 0.125,
                                                          stepSeconds: 0.125, startIndex: 0)
        var routing = ReferenceTimestampRouting()
        var selected: [ReferenceTimestampRouting.Selection] = []
        var featureFrames = 0
        for _ in 0..<10 {
            let request = try XCTUnwrap(scheduler.read(startIndex: 0, endIndex: 160, force: false,
                isAlmostFull: false) { request in
                    guard let result = try routing.route(primaryStream: 10, streamOrder: [10,20],
                        buffers: [10: t,20: t], from: t.timestamp(at: request.start),
                        through: t.timestamp(at: request.endExclusive-1), permissive: request.mayClipSearch) else { return false }
                    selected = result; return true
                })
            let selection = try XCTUnwrap(selected.first)
            let range = Int(selection.search.start)..<Int(selection.search.start)+selection.search.count
            let a = try routed.process(selectedChannelSamples: rows.map { Array($0[range]) }, overallContactQuality: 100)
            let b = try direct.process(selectedChannelSamples: rows.map { Array($0[Int(request.start)..<Int(request.endExclusive)]) },
                                       overallContactQuality: 100)
            XCTAssertEqual(a.status, b.status); XCTAssertEqual(a.filteredEpoch, b.filteredEpoch)
            XCTAssertEqual(a.bandPowers, b.bandPowers)
            if a.status == .featuresOnly { featureFrames += 1 }
            XCTAssertNil(a.command)
        }
        XCTAssertEqual(featureFrames, 3)
    }
    func testClosestHelperRetainsSentinelsAndDirectionDependentTies() throws {
        let ascending = try buffer([1,2,3,100], start: 10)
        XCTAssertEqual(try ascending.closest(to: 2.5), .init(timestamp: 2, index: 11))
        let descending = try buffer([1,98,99,100], start: 10)
        XCTAssertEqual(try descending.closest(to: 98.5), .init(timestamp: 99, index: 12))
        XCTAssertEqual(try ascending.closest(to: 0), .init(timestamp: -2, index: -1))
        XCTAssertEqual(try ascending.closest(to: 101), .init(timestamp: -1, index: -1))
        XCTAssertEqual(try buffer([]).closest(to: 1), .init(timestamp: -1, index: -1))
        XCTAssertEqual(try buffer([4],start: 30).closest(to: 4), .init(timestamp: 4, index: 30))
        XCTAssertEqual(try ascending.closest(to: 3), .init(timestamp: 3, index: 12))
        XCTAssertEqual(try ascending.closest(to: 100), .init(timestamp: 100, index: 13))
    }
    func testMalformedTimestampsAndBoundsAreExplicit() throws {
        for values in [[0.0], [1,1], [2,1], [.nan], [.infinity]] {
            XCTAssertThrowsError(try buffer(values))
        }
        XCTAssertThrowsError(try buffer([1], start: Int64.max))
        let b = try buffer([1])
        XCTAssertThrowsError(try b.search(cursor: -1, from: 0, through: 1))
        XCTAssertThrowsError(try b.search(cursor: 0, from: 2, through: 1))
        XCTAssertThrowsError(try b.timestamp(at: 1))
    }
}
