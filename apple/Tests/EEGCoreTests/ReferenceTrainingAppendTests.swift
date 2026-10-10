import XCTest
@testable import EEGCore

final class ReferenceTrainingAppendTests: XCTestCase {
    private let limits = ReferenceClassifierRebuild.TrainingLimits(maximumCells: 100,
        maximumEpochs: 20, maximumClasses: 4, maximumDistributionsPerClass: 8,
        storedMaximumEpochs: 10, storedMaximumDistributions: 4, maximumCanonicalDiagonalAdditions: 3)
    private func neutral() -> ReferenceTrainingBank.ClassEntry {
        .init(classReferenceID: 0, distributions: [.init(counts: [20, 20], mean: [0, 0],
            covariance: [[1, 0], [0, 1]], updateTime: 0)])
    }
    private func append(store: inout ReferenceTrainingDatabase.Store,
                        cache: inout ReferenceClassifierCache<ReferenceClassifierRebuild.Signature>,
                        metadata: [[Double]] = [[0, 0], [1, 0]], repetitions: Int = 1) throws -> ReferenceClassifierRebuild.Result {
        try ReferenceClassifierRebuild.append(actions: [0, 1], trainingAction: 1,
            pendingFeatures: Array(repeating: [[[1.0, 2], [3, 5]], [[3, 4], [4, 6]]], count: repetitions).flatMap { $0 },
            pendingTimestamps: Array(repeating: [[[100.0, 101]], [[102, 103]]], count: repetitions).flatMap { $0 }, featureChannelMetadata: metadata,
            limits: limits, store: &store, cache: &cache)
    }
    func testTrainingWritesBeforeMissingClassRejectsFit() throws {
        var store = ReferenceTrainingDatabase.Store()
        var cache = try ReferenceClassifierCache<ReferenceClassifierRebuild.Signature>(storageLimit: 4)
        let result = try append(store: &store, cache: &cache)
        XCTAssertEqual(result.route, .untrainedClass)
        XCTAssertNil(result.signature)
        XCTAssertEqual(store.featureRows[1], [[1, 3], [2, 5], [3, 4], [4, 6]])
        XCTAssertEqual(store.timestampRows[1], [[100], [101], [102], [103]])
        XCTAssertEqual(store.gaussian[1]?.distributions.first?.updateTime, 100)
        XCTAssertEqual(store.gaussian[1]?.distributions.first?.mean, [2.5, 4.5])
    }
    func testAcceptedFitAndSaveFailureStillRunCleanupInOrder() throws {
        var store = ReferenceTrainingDatabase.Store()
        store.gaussian[0] = neutral()
        var cache = try ReferenceClassifierCache<ReferenceClassifierRebuild.Signature>(storageLimit: 4)
        var built: ReferenceClassifierRebuild.Result?
        var operations: [String] = []
        let outcome = ReferenceTrainingPersistence.accept(build: {
            operations.append("build")
            built = try? append(store: &store, cache: &cache, repetitions: 5)
            return built?.signature != nil
        }, clearClassifier: { XCTFail("fit succeeded") }, save: {
            operations.append("save")
            XCTAssertNotNil(built?.signature)
            XCTAssertNotNil(store.gaussian[1])
            return false // Explicit test of caller-reported failure, not a mock successful disk save.
        }, clearErrors: { operations.append("errors") },
            updateTrainingCount: { operations.append("count") }, updateActions: { operations.append("actions") },
            updateBrainMapIfEligible: { operations.append("brain") }, unlockSettings: { operations.append("unlock") })
        XCTAssertEqual(built?.route, .fitted, built?.failureDescription ?? "no result")
        XCTAssertEqual(outcome, .saveFailed)
        XCTAssertEqual(operations, ["build", "save", "errors", "count", "actions", "brain", "unlock"])
        XCTAssertNotNil(cache.get([0, 1]))
    }
    func testFitRejectionPreservesTrainingDataAndClearsBeforeSaveAttempt() throws {
        var store = ReferenceTrainingDatabase.Store()
        store.gaussian[0] = neutral()
        var cache = try ReferenceClassifierCache<ReferenceClassifierRebuild.Signature>(storageLimit: 4)
        var operations: [String] = []
        var classifierPresent = true
        let outcome = ReferenceTrainingPersistence.accept(build: {
            operations.append("build")
            let result = try? append(store: &store, cache: &cache, metadata: [])
            XCTAssertEqual(result?.route, .fitRejected)
            return result?.signature != nil
        }, clearClassifier: { operations.append("clear"); classifierPresent = false }, save: {
            operations.append("save"); XCTAssertFalse(classifierPresent); return false
        }, clearErrors: {}, updateTrainingCount: {}, updateActions: {}, updateBrainMapIfEligible: {}, unlockSettings: {})
        XCTAssertEqual(outcome, .buildFailed(emptyBankSaved: false))
        XCTAssertEqual(operations, ["build", "clear", "save"])
        XCTAssertNotNil(store.gaussian[1]); XCTAssertNotNil(store.featureRows[1])
        XCTAssertTrue(cache.entries.isEmpty)
    }
    func testPendingCountAndEmptyListStopBeforeWrites() throws {
        var store = ReferenceTrainingDatabase.Store()
        var cache = try ReferenceClassifierCache<ReferenceClassifierRebuild.Signature>(storageLimit: 4)
        let empty = try ReferenceClassifierRebuild.append(actions: [0, 1], trainingAction: 1,
            pendingFeatures: [], pendingTimestamps: [], featureChannelMetadata: [], limits: limits,
            store: &store, cache: &cache)
        XCTAssertEqual(empty.route, .noNewData)
        XCTAssertThrowsError(try ReferenceClassifierRebuild.append(actions: [0, 1], trainingAction: 1,
            pendingFeatures: [[[1]]], pendingTimestamps: [], featureChannelMetadata: [], limits: limits,
            store: &store, cache: &cache))
        XCTAssertTrue(store.gaussian.isEmpty); XCTAssertTrue(store.featureRows.isEmpty)
    }

    func testFeatureWriteFailurePreventsGaussianSaveWithoutRollback() throws {
        var store = ReferenceTrainingDatabase.Store()
        var cache = try ReferenceClassifierCache<ReferenceClassifierRebuild.Signature>(storageLimit: 4)
        XCTAssertThrowsError(try ReferenceClassifierRebuild.append(actions: [0, 1], trainingAction: 1,
            pendingFeatures: [[[1, 2], [3, 5]]], pendingTimestamps: [[[100]]],
            featureChannelMetadata: [[0, 0], [1, 0]], limits: limits, store: &store, cache: &cache))
        XCTAssertEqual(store.featureRows[1], [[1, 3], [2, 5]])
        XCTAssertEqual(store.timestampRows[1], [[100]])
        XCTAssertNil(store.gaussian[1])
        XCTAssertTrue(cache.entries.isEmpty)
    }

    func testRetrainingInvalidatesOrdinaryCacheAndAppendsDistribution() throws {
        var store = ReferenceTrainingDatabase.Store()
        store.gaussian[0] = neutral()
        store.gaussian[1] = .init(classReferenceID: 1, distributions: [.init(counts: [20, 20], mean: [2, 4],
            covariance: [[1, 0], [0, 1]], updateTime: 20)])
        var cache = try ReferenceClassifierCache<ReferenceClassifierRebuild.Signature>(storageLimit: 4)
        let prior = try ReferenceClassifierRebuild.fit([neutral(), store.gaussian[1]!].map {
            .init(classReferenceID: $0.classReferenceID, distributions: $0.distributions)
        }, featureChannelMetadata: [[0, 0], [1, 0]], maximumClasses: 4, maximumCanonicalDiagonalAdditions: 3)
        try cache.put([0, 1], entry: .init(actions: [0, 1], payload: prior, reuseCount: 99))
        let updated = try append(store: &store, cache: &cache, repetitions: 5)
        XCTAssertEqual(updated.route, .fitted, updated.failureDescription ?? "")
        XCTAssertEqual(store.gaussian[1]?.distributions.count, 2)
        XCTAssertEqual(cache.get([0, 1])?.reuseCount, 0)
        XCTAssertEqual(store.featureRows[1]?.count, 10) // storage cap, not training-window truncation.
    }

    func testComposedAcceptanceSavesActualFittedValueBeforeUpdates() throws {
        var store = ReferenceTrainingDatabase.Store()
        store.gaussian[0] = neutral()
        var cache = try ReferenceClassifierCache<ReferenceClassifierRebuild.Signature>(storageLimit: 4)
        var classifier: ReferenceClassifierRebuild.Signature?
        var operations: [String] = []
        let result = try ReferenceClassifierRebuild.acceptTraining(actions: [0, 1], trainingAction: 1,
            pendingFeatures: Array(repeating: [[1.0, 2, 3, 4], [3, 5, 4, 6]], count: 5),
            pendingTimestamps: Array(repeating: [[100.0, 101, 102, 103]], count: 5),
            featureChannelMetadata: [[0, 0], [1, 0]], limits: limits, store: &store,
            cache: &cache, classifier: &classifier, saveClassifier: { value in
                XCTAssertNotNil(value); operations.append("save"); return false
            }, clearErrors: { operations.append("errors") }, updateTrainingCount: { operations.append("count") },
            updateActions: { operations.append("actions") }, updateBrainMapIfEligible: { operations.append("brain") },
            unlockSettings: { operations.append("unlock") })
        XCTAssertEqual(result.build.route, .fitted)
        XCTAssertEqual(result.outcome, .saveFailed)
        XCTAssertNotNil(classifier)
        XCTAssertNotNil(store.gaussian[1])
        XCTAssertEqual(operations, ["save", "errors", "count", "actions", "brain", "unlock"])
    }
}
