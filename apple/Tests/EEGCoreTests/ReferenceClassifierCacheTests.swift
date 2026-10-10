import XCTest
@testable import EEGCore
final class ReferenceClassifierCacheTests: XCTestCase {
    typealias Cache = ReferenceClassifierCache<String>
    private func entry(_ actions: [Int32], _ count: UInt64 = 0, _ payload: String = "fit") -> Cache.Entry {
        Cache.Entry(actions: actions, payload: payload, reuseCount: count)
    }
    func testKeysPreserveOrderDuplicatesAndDecimalFormatting() throws {
        XCTAssertEqual(Cache.key([1, 10, -2, 1]), "1,10,-2,1")
        XCTAssertEqual(Cache.key([]), "")
        var cache = try Cache(storageLimit: 8)
        try cache.put([1, 2], entry: entry([1, 2]))
        XCTAssertNotNil(cache.get([1, 2]))
        XCTAssertNil(cache.get([2, 1]))
        XCTAssertThrowsError(try cache.put([1, 2], entry: entry([2, 1])))
    }
    func testFrequencyEvictionAndLexicographicTieNotLRU() throws {
        var cache = try Cache(storageLimit: 8)
        cache.setMaximumCacheSize(2)
        try cache.put([2], entry: entry([2], 3))
        try cache.put([10], entry: entry([10], 3))
        _ = cache.get([10])
        try cache.put([4], entry: entry([4]))
        XCTAssertNil(cache.get([10]))
        XCTAssertNotNil(cache.get([2]))
        _ = cache.recordReuse([4])
        try cache.put([8], entry: entry([8]))
        XCTAssertNil(cache.get([4]))
        XCTAssertNotNil(cache.get([2]))
    }
    func testExistingKeyReplacementDoesNotEvictAtCapacity() throws {
        var cache = try Cache(storageLimit: 2)
        cache.setMaximumCacheSize(2)
        try cache.put([1], entry: entry([1]))
        try cache.put([2], entry: entry([2]))
        try cache.put([1], entry: entry([1], 7, "replacement"))
        XCTAssertEqual(cache.entries.count, 2)
        XCTAssertEqual(cache.get([1])?.payload, "replacement")
    }
    func testDisableAndSizeSetterClearAndDisabledPutReturnsFalse() throws {
        var cache = try Cache(storageLimit: 2)
        try cache.put([1], entry: entry([1]))
        cache.setMaximumCacheSize(0)
        XCTAssertEqual(cache.entries.count, 0)
        try cache.put([1], entry: entry([1]))
        cache.setEnabled(true)
        XCTAssertNotNil(cache.get([1]))
        cache.setEnabled(false)
        XCTAssertEqual(cache.entries.count, 0)
        XCTAssertFalse(try cache.put([9], entry: entry([8])))
        XCTAssertNil(cache.get([1]))
    }
    func testDirtyRemovalAndReuseWrapping() throws {
        var cache = try Cache(storageLimit: 4)
        try cache.put([1, 2], entry: entry([1, 2]))
        try cache.put([2, 4], entry: entry([2, 4]))
        try cache.put([8], entry: entry([8], .max))
        cache.removeDirtyClassifier(2)
        XCTAssertEqual(cache.entries.count, 1)
        XCTAssertEqual(cache.recordReuse([8])?.reuseCount, 0)
    }
    func testExplicitSafetyBoundRejectsUnlimitedGrowthAtomically() throws {
        var cache = try Cache(storageLimit: 1)
        try cache.put([1], entry: entry([1]))
        XCTAssertThrowsError(try cache.put([2], entry: entry([2])))
        XCTAssertEqual(cache.entries.count, 1)
        XCTAssertNotNil(cache.get([1]))
    }
}
