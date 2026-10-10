import XCTest
@testable import EEGCore

final class ReferenceNoiseHandlingTests: XCTestCase {
    typealias Cache = ReferenceErrorSetCache<Int>
    func testUnavailablePreservesStoredValidityWithoutCallingFitOrClassification() throws {
        var cache = try Cache(storageLimit: 4)
        let result: ReferenceNoiseHandling.Result<Int> = try ReferenceNoiseHandling.run(
            base: nil, featuresEmpty: false, storedValidity: false, channelMetadata: [],
            noisyChannels: [], actions: [], maximumNoisyChannels: 0, cache: &cache,
            rebuild: { _ in XCTFail(); return nil }, classify: { _ in XCTFail(); return 0 })
        XCTAssertFalse(result.valid); XCTAssertNil(result.output); XCTAssertEqual(result.route, .unavailable)
    }
    func testNoIntersectionUsesBaseEvenWhenConfiguredMaximumIsNegative() throws {
        var cache = try Cache(storageLimit: 4)
        let result = try ReferenceNoiseHandling.run(base: Cache.Entry(actions: [1], payload: 7),
            featuresEmpty: false, storedValidity: false, channelMetadata: [1], noisyChannels: [2],
            actions: [1], maximumNoisyChannels: -1, cache: &cache,
            rebuild: { _ in XCTFail(); return nil }, classify: { $0 })
        XCTAssertTrue(result.valid); XCTAssertEqual(result.output, 7); XCTAssertEqual(result.route, .base)
    }
    func testCacheHitPrecedesMaximumCheckAndIncrementsSharedCount() throws {
        var cache = try Cache(storageLimit: 4)
        let entry = Cache.Entry(actions: [1], reuseCount: 9, payload: 8)
        try cache.put(actions: [1], channels: [1, 1], entry: entry)
        let result = try ReferenceNoiseHandling.run(base: Cache.Entry(actions: [1], payload: 7),
            featuresEmpty: false, storedValidity: false, channelMetadata: [1], noisyChannels: [1, 1],
            actions: [1], maximumNoisyChannels: 0, cache: &cache,
            rebuild: { _ in XCTFail(); return nil }, classify: { $0 })
        XCTAssertEqual(result.route, .cached); XCTAssertEqual(result.output, 8); XCTAssertEqual(entry.reuseCount, 10)
    }
    func testDuplicateIDsCountTowardMaximumAndSuppressFit() throws {
        var cache = try Cache(storageLimit: 4)
        let result: ReferenceNoiseHandling.Result<Int> = try ReferenceNoiseHandling.run(
            base: Cache.Entry(actions: [1], payload: 7), featuresEmpty: false, storedValidity: true,
            channelMetadata: [1], noisyChannels: [1, 1], actions: [1], maximumNoisyChannels: 1,
            cache: &cache, rebuild: { _ in XCTFail(); return nil }, classify: { $0 })
        XCTAssertFalse(result.valid); XCTAssertNil(result.output); XCTAssertEqual(result.route, .tooManyChannels)
    }
    func testFitRejectionAndSuccessfulCachePopulation() throws {
        var cache = try Cache(storageLimit: 4)
        let base = Cache.Entry(actions: [1], payload: 7)
        let rejected: ReferenceNoiseHandling.Result<Int> = try ReferenceNoiseHandling.run(
            base: base, featuresEmpty: false, storedValidity: true, channelMetadata: [1],
            noisyChannels: [1], actions: [1], maximumNoisyChannels: 1, cache: &cache,
            rebuild: { _ in nil }, classify: { $0 })
        XCTAssertEqual(rejected.route, .buildRejected); XCTAssertFalse(rejected.valid); XCTAssertTrue(cache.entries.isEmpty)
        let accepted = try ReferenceNoiseHandling.run(base: base, featuresEmpty: false,
            storedValidity: false, channelMetadata: [1], noisyChannels: [1], actions: [1],
            maximumNoisyChannels: 1, cache: &cache,
            rebuild: { original in Cache.Entry(actions: original.actions, payload: original.payload + 1) },
            classify: { $0 })
        XCTAssertEqual(accepted.route, .rebuilt); XCTAssertEqual(accepted.output, 8)
        XCTAssertEqual(try cache.get(actions: [1], channels: [1])?.reuseCount, 1)
        XCTAssertEqual(base.payload, 7)
    }
    func testProcessedFeatureRoutingPreservesOriginalAndSkipsInvalidEpochs() throws {
        var processor = ReferenceProcessedEpoch()
        let first = try processor.process([2, 4], clean: true, backgroundEnabled: true)
        XCTAssertEqual(first.original, [2, 4]); XCTAssertEqual(first.processed, [0, 0])
        let rejected = try processor.process([100, 200], clean: false, backgroundEnabled: true)
        XCTAssertEqual(rejected.processed, []); XCTAssertEqual(processor.background.count, 1)
        let next = try processor.process([4, 8], clean: true, backgroundEnabled: true)
        XCTAssertEqual(next.processed, [1, 2])
        let bypass = try processor.process([8, 16], clean: true, backgroundEnabled: false)
        XCTAssertEqual(bypass.processed, bypass.original); XCTAssertEqual(processor.background.count, 2)
    }
}
