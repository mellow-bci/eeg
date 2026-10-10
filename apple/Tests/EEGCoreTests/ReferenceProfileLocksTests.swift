import XCTest
@testable import EEGCore
final class ReferenceProfileLocksTests: XCTestCase {
    func testAdvisoryWritesRemainPermittedAndEqualityControlsDiagnostic() throws {
        var locks = try ReferenceProfileLocks(maximumKeys: 2, maximumKeyBytes: 100)
        try locks.lock("setting")
        XCTAssertEqual(try locks.disposition(for: "setting", equalsPreviousQVariant: false), .init(writePermitted: true, emitLockedKeyDiagnostic: true))
        XCTAssertEqual(try locks.disposition(for: "setting", equalsPreviousQVariant: true), .init(writePermitted: true, emitLockedKeyDiagnostic: false))
        XCTAssertFalse(try locks.disposition(for: "other", equalsPreviousQVariant: false).emitLockedKeyDiagnostic)
    }
    func testRepeatedLockIsMembershipAndSingleUnlockRemovesIt() throws {
        var locks = try ReferenceProfileLocks(maximumKeys: 1, maximumKeyBytes: 20)
        try locks.lock("a"); try locks.lock("a"); XCTAssertEqual(locks.lockedKeys, ["a"])
        try locks.unlock("a"); try locks.unlock("a"); XCTAssertTrue(locks.lockedKeys.isEmpty)
    }
    func testTrainingWaitOnlyUnlocksControlThenCompletedUnlocksAll() throws {
        var locks = try ReferenceProfileLocks(maximumKeys: 11, maximumKeyBytes: 100)
        try locks.lock("cognitiv-trainingControl"); try locks.apply(.trainingStarted)
        XCTAssertEqual(locks.lockedKeys.count, 10)
        try locks.apply(.trainingWaitingForAcceptReject)
        XCTAssertEqual(locks.lockedKeys, Set(ReferenceProfileLocks.trainingKeys))
        try locks.apply(.trainingCompleted); XCTAssertTrue(locks.lockedKeys.isEmpty)
    }
    func testOverlappingNeutralAndTrainingLocksAreNotReferenceCounted() throws {
        var locks = try ReferenceProfileLocks(maximumKeys: 10, maximumKeyBytes: 100)
        try locks.apply(.trainingStarted); try locks.apply(.neutralSamplingStarted)
        try locks.apply(.neutralSamplingCompleted)
        XCTAssertEqual(locks.lockedKeys, ["cognitiv-autoSamplingNeutral"])
    }
    func testCapacityFailureIsAtomicAndAsciiSupportExplicit() throws {
        var locks = try ReferenceProfileLocks(maximumKeys: 1, maximumKeyBytes: 100)
        try locks.lock("existing")
        XCTAssertThrowsError(try locks.apply(.trainingStarted)); XCTAssertEqual(locks.lockedKeys, ["existing"])
        XCTAssertThrowsError(try locks.lock("é"))
        XCTAssertThrowsError(try locks.unlock(String(repeating: "x", count: 101)))
        XCTAssertThrowsError(try ReferenceProfileLocks(maximumKeys: 0, maximumKeyBytes: 1))
    }
}
