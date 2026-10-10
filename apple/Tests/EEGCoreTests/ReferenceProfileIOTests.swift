import XCTest
@testable import EEGCore

final class ReferenceProfileIOTests: XCTestCase {
    func testCacheHitNeverReadsStorage() {
        let result = ReferenceProfileIO.loadAttributes(cached: { 42 },
            checkMetadata: { XCTFail(); return -1 },
            readAttributes: { XCTFail(); return .failure(.init(code: -1)) },
            cacheLoaded: { _ in XCTFail() })
        XCTAssertEqual(try? result.get(), 42)
    }
    func testCacheMissOrdersMetadataReadAndCacheInsert() throws {
        var events: [String] = []
        let result = ReferenceProfileIO.loadAttributes(cached: { nil as Int? },
            checkMetadata: { events.append("metadata"); return 0 },
            readAttributes: { events.append("read"); return .success(7) },
            cacheLoaded: { events.append("cache:\($0)") })
        XCTAssertEqual(try result.get(), 7)
        XCTAssertEqual(events, ["metadata", "read", "cache:7"])
    }
    func testFailuresNeverInsertOrContinueAfterMetadataFailure() {
        let first = ReferenceProfileIO.loadAttributes(cached: { nil as Int? },
            checkMetadata: { 123 }, readAttributes: { XCTFail(); return .success(1) },
            cacheLoaded: { _ in XCTFail() })
        if case let .failure(error) = first { XCTAssertEqual(error.code, 123) } else { XCTFail() }
        let second = ReferenceProfileIO.loadAttributes(cached: { nil as Int? },
            checkMetadata: { 0 }, readAttributes: { .failure(.init(code: 456)) },
            cacheLoaded: { _ in XCTFail() })
        if case let .failure(error) = second { XCTAssertEqual(error.code, 456) } else { XCTFail() }
    }
    func testWorkerRetriesOnlyBusyCodeAndEmitsOnce() {
        var codes = [0x3303, 0x3303, 0]
        var completions: [Int] = []
        let result = ReferenceProfileIO.writeWorker(save: { codes.removeFirst() },
                                                   completed: { completions.append($0) })
        XCTAssertEqual(result, .init(attempts: 3, code: 0))
        XCTAssertEqual(completions, [0])
        let error = ReferenceProfileIO.writeWorker(save: { 0x3304 }, completed: { _ in })
        XCTAssertEqual(error, .init(attempts: 1, code: 0x3304))
    }
    func testWorkerStopsAfterSixAttempts() {
        var calls = 0
        let result = ReferenceProfileIO.writeWorker(save: { calls += 1; return 0x3303 }, completed: { _ in })
        XCTAssertEqual(calls, 6)
        XCTAssertEqual(result, .init(attempts: 6, code: 0x3303))
    }
    func testCompletionPropagatesDownstreamErrorWithoutMaskingWriteError() {
        var signals: [Int] = []
        XCTAssertEqual(ReferenceProfileIO.propagateCompletion(writeCode: 0x3304,
            followup: { XCTFail(); return 0 }, emit: { signals.append($0) }), 0x3304)
        XCTAssertEqual(ReferenceProfileIO.propagateCompletion(writeCode: 0,
            followup: { 912 }, emit: { signals.append($0) }), 912)
        XCTAssertEqual(signals, [0x3304, 912])
    }
}
