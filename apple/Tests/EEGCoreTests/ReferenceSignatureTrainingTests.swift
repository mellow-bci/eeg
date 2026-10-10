import XCTest
@testable import EEGCore

final class ReferenceSignatureTrainingTests: XCTestCase {
    private func distribution(_ mean: [Double], count: Double = 20, time: UInt32 = 0) -> ReferenceGaussianPooling.Distribution {
        .init(counts: Array(repeating: count, count: mean.count), mean: mean,
              covariance: mean.indices.map { r in mean.indices.map { c in r == c ? 1 : 0 } }, updateTime: time)
    }

    func testOrderedClassFoldAndClassReferenceFlag() throws {
        let source = ReferenceSignatureTraining.ClassAlgebra(classReferenceID: 17,
            distributions: [distribution([0], count: 2, time: 10), distribution([2], count: 2, time: 30),
                            distribution([4], count: 2, time: 90)])
        let value = try ReferenceSignatureTraining.combineClass(source, preserveClassReference: false)
        XCTAssertEqual(value.classReferenceID, -1)
        XCTAssertEqual(value.distribution?.counts, [6])
        XCTAssertEqual(value.distribution?.mean, [2])
        XCTAssertEqual(value.distribution?.updateTime, 55) // ((10+30)/2+90)/2.
        XCTAssertEqual(value.distribution?.covariance[0][0] ?? 0, 19.0 / 5, accuracy: 1e-12)
        let preserved = try ReferenceSignatureTraining.combineClass(source, preserveClassReference: true)
        XCTAssertEqual(preserved.classReferenceID, 17)
        XCTAssertEqual(preserved.distribution?.updateTime, 10)
        XCTAssertEqual(source.distributions[0].mean, [0])
    }

    func testEmptyFoldDoesNotInventGaussian() throws {
        let result = try ReferenceSignatureTraining.combineClass(.init(classReferenceID: 4, distributions: []), preserveClassReference: false)
        XCTAssertNil(result.distribution)
        XCTAssertEqual(result.classReferenceID, -1)
    }

    func testPoolingSelectionSliceAndChannelUnion() throws {
        let first = distribution(Array(repeating: 0, count: 20))
        let second = distribution((1...20).map(Double.init))
        let prepared = try ReferenceSignatureTraining.prepare([
            .init(classReferenceID: 3, distributions: [first]), .init(classReferenceID: 7, distributions: [second])
        ], featureChannelMetadata: (0..<20).map { [Double($0 % 3), 999, Double($0 % 4), 888] })
        XCTAssertEqual(prepared.selectedCoordinates, Array(13...19)) // ceil(sqrt(40))=7 strongest.
        XCTAssertEqual(prepared.sourceClassReferenceIDs, [3, 7])
        XCTAssertEqual(prepared.pooledClasses.map(\.classReferenceID), [-1, -1])
        XCTAssertEqual(prepared.selectedClasses[1].mean, (14...20).map(Double.init))
        XCTAssertEqual(prepared.selectedClasses[0].covariance.count, 7)
        XCTAssertEqual(prepared.channelsInUse, [0, 1, 2, 3])
    }

    func testChannelMappingUsesEvenColumnsTruncatesAndSorts() throws {
        XCTAssertEqual(try ReferenceSignatureTraining.extractChannels(coordinates: [1, 0],
            metadata: [[7.9, .nan, 2, .nan, 111], [2, .nan, 1.5, .nan, 222]]), [1, 2, 7])
        XCTAssertEqual(try ReferenceSignatureTraining.extractChannels(coordinates: [0], metadata: [[55]]), [])
        XCTAssertThrowsError(try ReferenceSignatureTraining.extractChannels(coordinates: [0], metadata: [[-1, 0]]))
    }

    func testAssemblyUsesUnitWeightsAndRejectsMalformedFit() throws {
        let p = try ReferenceSignatureTraining.prepare([
            .init(classReferenceID: 3, distributions: [distribution([0, 0])]),
            .init(classReferenceID: 7, distributions: [distribution([1, 2])])
        ], featureChannelMetadata: [[0, 0], [1, 0]])
        let pca = ReferenceGaussianPipeline.CenteredTransform(mean: [0.5, 1], basis: [[1, 0], [0, 1]])
        let canonical = ReferenceGaussianPipeline.CenteredTransform(mean: [0, 0], basis: [[1], [0]])
        let result = try ReferenceSignatureTraining.assemble(p, pca: pca, canonical: canonical,
            fittedClasses: [.init(mean: [-1], covariance: [[2]]), .init(mean: [1], covariance: [[3]])])
        XCTAssertEqual(result.classes.map { $0.components.count }, [1, 1])
        XCTAssertEqual(result.classes.map { $0.components[0].weight }, [1, 1])
        XCTAssertEqual(result.classes.map { $0.components[0].mean }, [[-1], [1]])
        XCTAssertThrowsError(try ReferenceSignatureTraining.assemble(p, pca: pca, canonical: canonical,
            fittedClasses: [.init(mean: [-1], covariance: [[2]])]))
    }

    func testPrepareRejectsInvalidClassAndEmptyData() {
        let metadata = [[0.0, 0]]
        XCTAssertThrowsError(try ReferenceSignatureTraining.prepare([
            .init(classReferenceID: -1, distributions: [distribution([0])]),
            .init(classReferenceID: 1, distributions: [distribution([1])])
        ], featureChannelMetadata: metadata))
        XCTAssertThrowsError(try ReferenceSignatureTraining.prepare([
            .init(classReferenceID: 0, distributions: []), .init(classReferenceID: 1, distributions: [])
        ], featureChannelMetadata: metadata))
    }

    func testRunRequiresFitAndPropagatesItsFailureAfterPreparation() {
        enum Failure: Error { case deliberatelyUnavailableFit }
        var receivedPreparedData = false
        XCTAssertThrowsError(try ReferenceSignatureTraining.run([
            .init(classReferenceID: 0, distributions: [distribution([0, 0])]),
            .init(classReferenceID: 1, distributions: [distribution([1, 2])])
        ], featureChannelMetadata: [[0, 0], [1, 0]], fit: { preparation in
            receivedPreparedData = preparation.selectedClasses.count == 2 && preparation.selectedCoordinates == [0, 1]
            throw Failure.deliberatelyUnavailableFit
        })) { error in
            XCTAssertTrue(error is Failure)
        }
        XCTAssertTrue(receivedPreparedData)
    }
}
