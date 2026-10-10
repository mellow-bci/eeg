import XCTest
@testable import EEGCore

final class ReferenceDatabaseOrchestrationTests: XCTestCase {
    func testDriverErrorDoesNotWriteOrSleep() {
        let result = ReferenceDatabaseOrchestration.writeDocument(
            acquireDriver: { Result<Int, ReferenceProfileIO.Failure>.failure(.init(code: 123)) },
            write: { _ in XCTFail(); return 0 }, sleepMilliseconds: { _ in XCTFail() })
        XCTAssertEqual(result, .init(attempts: 0, code: 123))
    }
    func testDatabaseRetryBoundIncludesLastSleep() {
        var sleeps: [Int] = []
        let result = ReferenceDatabaseOrchestration.writeDocument(acquireDriver: { .success(1) },
            write: { XCTAssertEqual($0, 1); return 0x3102 }, sleepMilliseconds: { sleeps.append($0) })
        XCTAssertEqual(result, .init(attempts: 10, code: 0x3102))
        XCTAssertEqual(sleeps, Array(repeating: 5, count: 10))
    }
    func testDatabaseRetrySuccessAndUnrelatedFailure() {
        var values = [0x3102, 0x3102, 0]
        var sleeps = 0
        let result = ReferenceDatabaseOrchestration.writeDocument(acquireDriver: { .success(1) },
            write: { _ in values.removeFirst() }, sleepMilliseconds: { _ in sleeps += 1 })
        XCTAssertEqual(result, .init(attempts: 3, code: 0)); XCTAssertEqual(sleeps, 2)
        let failed = ReferenceDatabaseOrchestration.writeDocument(acquireDriver: { .success(1) },
            write: { _ in 0x3303 }, sleepMilliseconds: { _ in XCTFail() })
        XCTAssertEqual(failed, .init(attempts: 1, code: 0x3303))
    }
    func testChangeNotificationRequiresAllThreeGates() {
        for code in [0, 31] {
            for available in [false, true] {
                for notify in [false, true] {
                    var calls = 0
                    XCTAssertEqual(ReferenceDatabaseOrchestration.saveDocument(notifyChanges: notify,
                        updaterAvailable: available, save: { code }, addChanges: { calls += 1 }), code)
                    XCTAssertEqual(calls, code == 0 && available && notify ? 1 : 0)
                }
            }
        }
    }
    func testCacheRemainsPublishedWhenMetadataOrAttributeWriteFails() throws {
        for metadataCode in [0, 77] {
            var events: [String] = []
            let code = try ReferenceDatabaseOrchestration.updateProfileCache(profileID: "own", attributesID: "own",
                publishCache: { events.append("cache") }, saveMetadata: { events.append("metadata"); return metadataCode },
                saveAttributes: { events.append("attributes"); return 88 })
            XCTAssertEqual(code, metadataCode == 0 ? 88 : 77)
            XCTAssertEqual(events, metadataCode == 0 ? ["cache", "metadata", "attributes"] : ["cache", "metadata"])
        }
    }
    func testMismatchedIDsAreExplicitUnsupportedDomain() {
        XCTAssertThrowsError(try ReferenceDatabaseOrchestration.updateProfileCache(profileID: "a", attributesID: "b",
            publishCache: { XCTFail() }, saveMetadata: { XCTFail(); return 0 }, saveAttributes: { XCTFail(); return 0 }))
    }
    func testQueuedInvocationFailureDoesNotBecomeDurability() {
        let result = ReferenceDatabaseOrchestration.saveAttributes(queued: true, invokeSave: { false },
            writeFile: { XCTFail(); return 0 }, saveMetadataAfterFile: { XCTFail(); return 0 })
        XCTAssertEqual(result, .queued(invocationAccepted: false, reportedCode: 0))
    }
    func testSynchronousFileRetryThenMetadataFailure() {
        var codes = [0x3303, 0]
        var events: [String] = []
        let result = ReferenceDatabaseOrchestration.saveAttributes(queued: false, invokeSave: { XCTFail(); return true },
            writeFile: { events.append("file"); return codes.removeFirst() },
            saveMetadataAfterFile: { events.append("metadata"); return 15 })
        XCTAssertEqual(result, .synchronous(fileAttempts: 2, code: 15))
        XCTAssertEqual(events, ["file", "file", "metadata"])
    }
    func testFileFailureSkipsMetadataAndMetadataIsUUIDOnly() {
        let result = ReferenceDatabaseOrchestration.saveAttributes(queued: false, invokeSave: { XCTFail(); return true },
            writeFile: { 0x3304 }, saveMetadataAfterFile: { XCTFail(); return 0 })
        XCTAssertEqual(result, .synchronous(fileAttempts: 1, code: 0x3304))
        XCTAssertEqual(ReferenceDatabaseOrchestration.attributeMetadata(profileID: "own"), ["uuid": .string("own")])
    }
}
