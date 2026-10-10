import XCTest
@testable import EEGCore
final class ReferenceErrorSetCacheTests: XCTestCase {
    typealias Cache = ReferenceErrorSetCache<String>
    func testExactOrderedKeyIncludingEmptyAndUnsignedChannels() {
        XCTAssertEqual(Cache.key(actions: [-1, 2, 2], channels: [UInt64.max, 0]), "-1,2,2:18446744073709551615,0")
        XCTAssertEqual(Cache.key(actions: [], channels: []), ":")
        XCTAssertNotEqual(Cache.key(actions: [1, 2], channels: [3, 4]), Cache.key(actions: [2, 1], channels: [3, 4]))
        XCTAssertNotEqual(Cache.key(actions: [1], channels: [3, 4]), Cache.key(actions: [1], channels: [4, 3]))
    }
    func testGetSharesIdentityAndDoesNotIncrementReuseCount() throws {
        var bank = try Cache(storageLimit: 3)
        let entry = Cache.Entry(actions: [1], reuseCount: 4, payload: "fit")
        try bank.put(actions: [1], channels: [3], entry: entry)
        let found = try XCTUnwrap(bank.get(actions: [1], channels: [3]))
        XCTAssertTrue(found === entry); XCTAssertEqual(found.reuseCount, 4)
        found.reuseCount = 10; found.payload = "updated"
        XCTAssertEqual(try bank.get(actions: [1], channels: [3])?.payload, "updated")
        XCTAssertNil(try bank.get(actions: [1], channels: [4]))
    }
    func testMinimumReuseEvictionAndLexicalTie() throws {
        var bank = try Cache(storageLimit: 4); bank.setMaximumClassifiers(2)
        try bank.put(actions: [2], channels: [], entry: .init(actions: [2], reuseCount: 3, payload: "two"))
        try bank.put(actions: [10], channels: [], entry: .init(actions: [10], reuseCount: 3, payload: "ten"))
        _ = try bank.get(actions: [10], channels: [])
        try bank.put(actions: [4], channels: [], entry: .init(actions: [4], payload: "four"))
        XCTAssertNil(try bank.get(actions: [10], channels: []))
        XCTAssertNotNil(try bank.get(actions: [2], channels: []))
        try bank.put(actions: [8], channels: [], entry: .init(actions: [8], payload: "eight"))
        XCTAssertNil(try bank.get(actions: [4], channels: []))
    }
    func testReplacementBypassesEvictionAndSetLimitAlwaysClears() throws {
        var bank = try Cache(storageLimit: 2); bank.setMaximumClassifiers(1)
        try bank.put(actions: [1], channels: [], entry: .init(actions: [1], payload: "a"))
        try bank.put(actions: [1], channels: [], entry: .init(actions: [1], payload: "b"))
        XCTAssertEqual(bank.entries.count, 1)
        XCTAssertEqual(try bank.get(actions: [1], channels: [])?.payload, "b")
        bank.setMaximumClassifiers(1); XCTAssertTrue(bank.entries.isEmpty)
        bank.setMaximumClassifiers(0)
        try bank.put(actions: [1], channels: [], entry: .init(actions: [1], payload: "a"))
        bank.clear(); XCTAssertTrue(bank.entries.isEmpty)
    }
    func testNonnullPutAndGetTimeActionAssertion() throws {
        var bank = try Cache(storageLimit: 1)
        XCTAssertThrowsError(try bank.put(actions: [1], channels: [], entry: nil))
        try bank.put(actions: [1], channels: [], entry: .init(actions: [2], payload: "wrong actions"))
        XCTAssertThrowsError(try bank.get(actions: [1], channels: []))
        XCTAssertThrowsError(try bank.put(actions: [3], channels: [], entry: .init(actions: [3], payload: "full")))
        XCTAssertEqual(bank.entries.count, 1)
    }
}
