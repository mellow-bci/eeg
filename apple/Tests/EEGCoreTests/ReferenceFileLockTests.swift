import XCTest
@testable import EEGCore

final class ReferenceFileLockTests: XCTestCase {
    func testSuccessfulOperationOrderAndLockFilename() throws {
        XCTAssertEqual(ReferenceFileLock.lockPath(dataPath: "/profiles/a"), "/profiles/a.lock")
        var events: [String] = []
        let result = try ReferenceFileLock.perform(timeoutMilliseconds: 1000,
            tryLock: { events.append("try:\($0)"); return true },
            acquisitionFailed: { XCTFail() }, isLocked: { events.append("check"); return true },
            unlock: { events.append("unlock") }, dispose: { events.append("dispose") },
            operation: { events.append("operation"); return 7 })
        if case let .performed(value) = result { XCTAssertEqual(value, 7) } else { XCTFail() }
        XCTAssertEqual(events, ["try:1000", "check", "operation", "unlock", "dispose"])
    }
    func testFailedLockNeverExecutesDataOperationButStillUnlocks() throws {
        var events: [String] = []
        let result = try ReferenceFileLock.perform(timeoutMilliseconds: 1000,
            tryLock: { _ in events.append("try"); return false },
            acquisitionFailed: { events.append("diagnostic") }, isLocked: { events.append("check"); return false },
            unlock: { events.append("unlock") }, dispose: { events.append("dispose") },
            operation: { XCTFail(); return 0 })
        if case .unavailable = result {} else { XCTFail() }
        XCTAssertEqual(events, ["try", "diagnostic", "check", "unlock", "dispose"])
    }
    func testCallerUsesActualLockStateInsteadOfTryResult() throws {
        let result = try ReferenceFileLock.perform(timeoutMilliseconds: 0,
            tryLock: { _ in false }, acquisitionFailed: {}, isLocked: { true },
            unlock: {}, dispose: {}, operation: { 13 })
        if case let .performed(value) = result { XCTAssertEqual(value, 13) } else { XCTFail() }
        let denied = try ReferenceFileLock.perform(timeoutMilliseconds: 0,
            tryLock: { _ in true }, acquisitionFailed: { XCTFail() }, isLocked: { false },
            unlock: {}, dispose: {}, operation: { XCTFail(); return 0 })
        if case .unavailable = denied {} else { XCTFail() }
    }
    func testThrownOperationReleasesLockAndPreservesError() {
        enum Failure: Error { case disk }
        var cleanup: [String] = []
        XCTAssertThrowsError(try ReferenceFileLock.perform(timeoutMilliseconds: 1000,
            tryLock: { _ in true }, acquisitionFailed: {}, isLocked: { true },
            unlock: { cleanup.append("unlock") }, dispose: { cleanup.append("dispose") },
            operation: { () throws -> Int in throw Failure.disk })) { error in
                guard case Failure.disk = error else { return XCTFail() }
            }
        XCTAssertEqual(cleanup, ["unlock", "dispose"])
    }
    func testUnsupportedNegativeWaitDoesNotTouchLockCallbacks() {
        XCTAssertThrowsError(try ReferenceFileLock.perform(timeoutMilliseconds: -1,
            tryLock: { _ in XCTFail(); return false }, acquisitionFailed: { XCTFail() },
            isLocked: { XCTFail(); return false }, unlock: { XCTFail() }, dispose: { XCTFail() },
            operation: { XCTFail(); return 0 }))
    }
}
