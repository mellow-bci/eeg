import XCTest
@testable import EEGCore

final class ReferenceClassifierRebuildTests: XCTestCase {
    private func bank() -> [ReferenceTrainingBank.ClassEntry] {
        [Int32(0), 1].map { id in
            .init(classReferenceID: id, distributions: [.init(counts: [20, 20],
                mean: id == 0 ? [0, 0] : [2, 4], covariance: [[1, 0], [0, 1]], updateTime: 0)])
        }
    }

    func testTypedDatabaseFitThenCacheBypassesStorageAndScores() throws {
        var store = ReferenceTrainingDatabase.Store()
        _ = try ReferenceTrainingDatabase.saveGaussian(classIDs: [0, 1], entries: bank(),
            append: false, maximumDistributions: 4, store: &store)
        var cache = try ReferenceClassifierCache<ReferenceClassifierRebuild.Signature>(storageLimit: 4)
        var reads: [String] = []
        func rebuild() throws -> ReferenceClassifierRebuild.Result {
            try ReferenceClassifierRebuild.run(actions: [0, 1], trainingAction: 1,
                featureChannelMetadata: [[0, 0], [1, 0]], maximumClasses: 4,
                maximumCanonicalDiagonalAdditions: 3, cache: &cache,
                loadFeatureData: {
                    reads.append("features")
                    _ = try ReferenceTrainingDatabase.loadFeatures(classIDs: [0, 1], store: store)
                }, loadGaussianData: {
                    reads.append("gaussians")
                    return try ReferenceTrainingDatabase.loadGaussian(classIDs: [0, 1], store: store)
                })
        }
        let fitted = try rebuild()
        XCTAssertEqual(fitted.route, .fitted)
        XCTAssertEqual(reads, ["features", "gaussians"])
        let signature = try XCTUnwrap(fitted.signature)
        let parameters = ReferenceGaussianPipeline.Parameters(pca: signature.pca,
            canonical: signature.canonical, canonicalClassCount: 2, classes: signature.classes,
            classPriors: [1, 1], neutralScale: 1)
        let left = try ReferenceGaussianPipeline.infer(featureVector: [0, 0], parameters: parameters)
        let right = try ReferenceGaussianPipeline.infer(featureVector: [2, 4], parameters: parameters)
        XCTAssertGreaterThan(left.classDensity[0], left.classDensity[1])
        XCTAssertGreaterThan(right.classDensity[1], right.classDensity[0])
        XCTAssertEqual(try rebuild().route, .cached)
        XCTAssertEqual(reads, ["features", "gaussians"])
        XCTAssertEqual(cache.get([0, 1])?.reuseCount, 1)
    }

    func testInactiveAndUntrainedDoNotInventClassifier() throws {
        var cache = try ReferenceClassifierCache<ReferenceClassifierRebuild.Signature>(storageLimit: 4)
        var reads = 0
        let inactive = try ReferenceClassifierRebuild.run(actions: [0, 1], trainingAction: 2,
            featureChannelMetadata: [], maximumClasses: 4, maximumCanonicalDiagonalAdditions: 3,
            cache: &cache, loadFeatureData: { reads += 1 }, loadGaussianData: { [] })
        XCTAssertEqual(inactive.route, .inactiveTrainingAction)
        XCTAssertEqual(reads, 0)
        let empty = try ReferenceClassifierRebuild.run(actions: [0, 1], trainingAction: 1,
            featureChannelMetadata: [], maximumClasses: 4, maximumCanonicalDiagonalAdditions: 3,
            cache: &cache, loadFeatureData: { reads += 1 }, loadGaussianData: {
                [.init(classReferenceID: 0, distributions: []), .init(classReferenceID: 1, distributions: [])]
            })
        XCTAssertEqual(empty.route, .untrainedClass)
        XCTAssertNil(empty.signature)
        XCTAssertEqual(cache.entries.count, 0)
    }

    func testMalformedFitAndClassCountCannotPopulateCache() throws {
        var cache = try ReferenceClassifierCache<ReferenceClassifierRebuild.Signature>(storageLimit: 4)
        let rejected = try ReferenceClassifierRebuild.run(actions: [0, 1], trainingAction: 1,
            featureChannelMetadata: [], maximumClasses: 4, maximumCanonicalDiagonalAdditions: 3,
            cache: &cache, loadFeatureData: {}, loadGaussianData: { self.bank() })
        XCTAssertEqual(rejected.route, .fitRejected)
        XCTAssertNil(rejected.signature)
        XCTAssertNotNil(rejected.failureDescription)
        XCTAssertTrue(cache.entries.isEmpty)
        XCTAssertThrowsError(try ReferenceClassifierRebuild.run(actions: [0, 1], trainingAction: 1,
            featureChannelMetadata: [], maximumClasses: 4, maximumCanonicalDiagonalAdditions: 3,
            cache: &cache, loadFeatureData: {}, loadGaussianData: { [] }))
        XCTAssertTrue(cache.entries.isEmpty)
    }

    func testNoisyMissUsesOrdinaryFitWithoutInventedChannelMask() throws {
        typealias Cache = ReferenceErrorSetCache<ReferenceClassifierRebuild.Signature>
        let signature = try ReferenceClassifierRebuild.fit(bank().map {
            .init(classReferenceID: $0.classReferenceID, distributions: $0.distributions)
        }, featureChannelMetadata: [[0, 0], [1, 0]], maximumClasses: 4,
            maximumCanonicalDiagonalAdditions: 3)
        var ordinary = try ReferenceClassifierCache<ReferenceClassifierRebuild.Signature>(storageLimit: 4)
        var errors = try Cache(storageLimit: 4)
        let base = Cache.Entry(actions: [0, 1], payload: signature)
        let rebuilt = try ReferenceNoiseHandling.run(base: base, featuresEmpty: false,
            storedValidity: true, channelMetadata: [0, 1], noisyChannels: [0], actions: [0, 1],
            maximumNoisyChannels: 1, cache: &errors, rebuild: { _ in
                let result = try ReferenceClassifierRebuild.run(actions: [0, 1], trainingAction: 1,
                    featureChannelMetadata: [[0, 0], [1, 0]], maximumClasses: 4,
                    maximumCanonicalDiagonalAdditions: 3, cache: &ordinary,
                    loadFeatureData: {}, loadGaussianData: { self.bank() })
                return result.signature.map { Cache.Entry(actions: [0, 1], payload: $0) }
            }, classify: { $0.preparation.selectedCoordinates })
        XCTAssertEqual(rebuilt.route, .rebuilt)
        XCTAssertTrue(rebuilt.valid)
        XCTAssertEqual(rebuilt.output, signature.preparation.selectedCoordinates)
        XCTAssertEqual(try errors.get(actions: [0, 1], channels: [0])?.reuseCount, 1)
        XCTAssertNotNil(ordinary.get([0, 1]))
    }

    func testPublicFitWithSingularInputRetainsScoreableSubspace() throws {
        // Regression at the full fitter boundary: singular input is not the same
        // as a singular final class density. No variance floor is introduced.
        let covariance = [[4.0, 4, 0], [4, 4, 0], [0, 0, 2]]
        let means = [[2.0, 2, 6], [4, 4, 6]]
        let classes = (0..<2).map { index in
            ReferenceSignatureTraining.ClassAlgebra(classReferenceID: Int32(index), distributions: [
                .init(counts: [20,20,20], mean: means[index], covariance: covariance, updateTime: UInt32(index))])
        }
        let signature = try ReferenceClassifierRebuild.fit(classes,
            featureChannelMetadata: [[0,0],[1,0],[2,0]], maximumClasses: 2,
            maximumCanonicalDiagonalAdditions: 3)
        let parameters = ReferenceGaussianPipeline.Parameters(pca: signature.pca,
            canonical: signature.canonical, canonicalClassCount: 2,
            classes: signature.classes, classPriors: [1,1], neutralScale: 1)
        for index in means.indices {
            let features = signature.preparation.selectedCoordinates.map { means[index][$0] }
            let result = try ReferenceGaussianPipeline.infer(featureVector: features, parameters: parameters)
            XCTAssertGreaterThan(result.classDensity[index], result.classDensity[1-index])
            XCTAssertTrue(result.posterior.allSatisfy(\.isFinite))
        }
    }
}
