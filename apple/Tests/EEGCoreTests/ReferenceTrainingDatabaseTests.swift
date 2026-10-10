import XCTest
@testable import EEGCore

final class ReferenceTrainingDatabaseTests: XCTestCase {
    private func distribution(_ mean: Double, time: UInt32) -> ReferenceGaussianPooling.Distribution {
        .init(counts: [2], mean: [mean], covariance: [[1]], updateTime: time)
    }
    func testGaussianOrderMissingAndPayloadIdentity() throws {
        var store = ReferenceTrainingDatabase.Store()
        store.gaussian[3] = .init(classReferenceID: 7, distributions: [distribution(4,time: 12)])
        let loaded = try ReferenceTrainingDatabase.loadGaussian(classIDs: [3,1,3], store: store)
        XCTAssertEqual(loaded.map(\.classReferenceID), [7,1,7])
        XCTAssertEqual(loaded[1].distributions, [])
        store.gaussian[1] = .init(classReferenceID: -1, distributions: [])
        XCTAssertThrowsError(try ReferenceTrainingDatabase.loadGaussian(classIDs: [1], store: store))
    }
    func testAppendPoolsOldestFirstAndRetainsTimestampArithmetic() throws {
        var store = ReferenceTrainingDatabase.Store()
        let old = distribution(0,time: 10), second = distribution(2,time: 20), new = distribution(4,time: 40)
        store.gaussian[2] = .init(classReferenceID: 9, distributions: [old,second])
        XCTAssertEqual(try ReferenceTrainingDatabase.saveGaussian(classIDs: [2],
            entries: [.init(classReferenceID: 2, distributions: [new])], append: true,
            maximumDistributions: 2, store: &store), .saved)
        let bank = store.gaussian[2]!
        XCTAssertEqual(bank.classReferenceID, 9)
        XCTAssertEqual(bank.distributions.count, 2)
        XCTAssertEqual(bank.distributions[0].mean, [1])
        XCTAssertEqual(bank.distributions[0].counts, [4])
        XCTAssertEqual(bank.distributions[0].updateTime, 15)
        XCTAssertEqual(bank.distributions[1], new)
        _ = try ReferenceTrainingDatabase.saveGaussian(classIDs: [2], entries: [.init(classReferenceID: 5,
            distributions: [new])], append: false, maximumDistributions: 0, store: &store)
        XCTAssertEqual(store.gaussian[2]?.classReferenceID, 5)
    }
    func testIgnoredCountsAndSequentialGaussianFailure() throws {
        var store = ReferenceTrainingDatabase.Store()
        XCTAssertEqual(try ReferenceTrainingDatabase.saveGaussian(classIDs: [], entries: [], append: false,
            maximumDistributions: 1, store: &store), .ignoredInvalidCounts)
        XCTAssertThrowsError(try ReferenceTrainingDatabase.saveGaussian(classIDs: [1,2], entries: [
            .init(classReferenceID: 8, distributions: []), .init(classReferenceID: -1, distributions: [])],
            append: false, maximumDistributions: 1, store: &store))
        XCTAssertEqual(store.gaussian[1]?.classReferenceID, 8)
        XCTAssertNil(store.gaussian[2])
    }
    func testFeaturesTransposeAppendTailCapAndSkippedSlot() throws {
        var store = ReferenceTrainingDatabase.Store()
        _ = try ReferenceTrainingDatabase.saveFeatures(classIDs: [2,3],
            features: [[[1,2],[10,20]], []], timestamps: [[[100,200]], [[9]]],
            maximumEpochs: 3, store: &store)
        _ = try ReferenceTrainingDatabase.saveFeatures(classIDs: [2], features: [[[3,4],[30,40]]],
            timestamps: [[[300,400]]], maximumEpochs: 3, store: &store)
        XCTAssertEqual(store.featureRows[2], [[2,20],[3,30],[4,40]])
        let loaded = try ReferenceTrainingDatabase.loadFeatures(classIDs: [3,2,2], store: store)
        XCTAssertEqual(loaded.features, [[],[[2,3,4],[20,30,40]],[[2,3,4],[20,30,40]]])
        XCTAssertEqual(loaded.timestamps, [[],[[200,300,400]],[[200,300,400]]])
        XCTAssertNil(store.timestampRows[3])
    }
    func testCountAssertionOccursAfterBothWritesWithoutRollback() throws {
        var store = ReferenceTrainingDatabase.Store()
        XCTAssertThrowsError(try ReferenceTrainingDatabase.saveFeatures(classIDs: [1],
            features: [[[1,2]]], timestamps: [[[100]]], maximumEpochs: 0, store: &store)) { error in
            XCTAssertEqual(error as? ReferenceTrainingDatabase.InputError, .epochCountMismatch)
        }
        XCTAssertEqual(store.featureRows[1], [[1],[2]])
        XCTAssertEqual(store.timestampRows[1], [[100]])
        XCTAssertEqual(try ReferenceTrainingDatabase.saveFeatures(classIDs: [2], features: [], timestamps: [],
            maximumEpochs: 1, store: &store), .ignoredInvalidCounts)
    }
}
