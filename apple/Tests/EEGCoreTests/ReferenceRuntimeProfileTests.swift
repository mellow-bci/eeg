import XCTest
@testable import EEGCore

final class ReferenceRuntimeProfileTests: XCTestCase {
    typealias Codec = ReferenceProfileCodec
    typealias Runtime = ReferenceRuntimeProfile
    typealias Kernel = ReferenceGaussianPipeline
    private func matrix(_ rows: [[Double]]) throws -> Codec.Matrix { try .fromRows(rows) }
    private func profile(retained: UInt64 = 1, weightRow: Bool = false) throws -> Codec.Classifier {
        .init(weightMeanVariances: [
            .init(weight: try matrix(weightRow ? [[0.2,0.8]] : [[0.2],[0.8]]),
                  mean: try matrix([[-2,3]]), variances: [try matrix([[1]]),try matrix([[4]])]),
            .init(weight: try matrix([[1]]),mean: try matrix([[1]]),variances: [try matrix([[2]])])],
            classRefIDs: [9,2], uniqueFeatureIndices: [2,0],
            coeff: try matrix([[2,7],[3,11]]), pcMeans: try matrix([[1,2]]),
            eigenvec: try matrix([[4,99]]),meanTot: try matrix([[5]]),
            channelInUse: try matrix([[2,0]]),numOfValidFeatures: retained,useCount: 7)
    }
    func testAsymmetricComponentsAndPCAColumnTruncationPreserveLogicalOrientation() throws {
        let runtime = try Runtime.runtime(profile(),classPriors: [0.3,0.7],neutralScale: 2)
        let result = try Runtime.infer(featureVector: [4,999,6],runtime: runtime)
        // Select [6,4], center [1,2], multiply first PCA column [2,3] =>16.
        // Canonical center5, first basis4 =>44; ignored PCA column must not leak.
        XCTAssertEqual(result.pcaFeatures,[16])
        XCTAssertEqual(result.canonicalFeatures,[44])
        XCTAssertEqual(runtime.classReferenceIDs,[9,2])
        XCTAssertEqual(runtime.useCount,7)
        let expected = try Kernel.mixtureDensity([44],mixture: .init(components: [
            .init(weight: 0.2,mean: [-2],covariance: [[1]]),
            .init(weight: 0.8,mean: [3],covariance: [[4]])]))
        XCTAssertEqual(result.classDensity[0],expected.value)
        XCTAssertEqual(result.classPeakDensity[0],expected.atMean)
    }
    func testSchemaAcceptanceCannotReplaceExecutableShapeValidation() throws {
        for retained in [UInt64(0),3] {
            XCTAssertThrowsError(try Runtime.runtime(profile(retained: retained),classPriors: [1,1],neutralScale: 1))
        }
        // Retaining2 is in PCA range but incompatible with one-row canonical inputs.
        XCTAssertThrowsError(try Runtime.runtime(profile(retained: 2),classPriors: [1,1],neutralScale: 1))
        XCTAssertThrowsError(try Runtime.runtime(profile(weightRow: true),classPriors: [1,1],neutralScale: 1))
        let runtime = try Runtime.runtime(profile(),classPriors: [1,1],neutralScale: 1)
        XCTAssertThrowsError(try Runtime.infer(featureVector: [0,1],runtime: runtime))
        XCTAssertThrowsError(try Runtime.runtime(profile(),classPriors: [1],neutralScale: 1))
    }
    func testActualIndependentFitSurvivesTypedJSONGzipEncryptedInverseAndScores() throws {
        let classes: [ReferenceSignatureTraining.ClassAlgebra] = [Int32(0),1].map { id in
            .init(classReferenceID: id,distributions: [.init(counts: [20,20],
                mean: id == 0 ? [0,0] : [2,4],covariance: [[1,0],[0,1]],updateTime: 0)])
        }
        let signature = try ReferenceClassifierRebuild.fit(classes,featureChannelMetadata: [[0,0],[1,0]],
            maximumClasses: 4,maximumCanonicalDiagonalAdditions: 3)
        let profile = try Runtime.classifier(signature,numOfValidFeatures: signature.pca.basis[0].count,useCount: 3)
        let before = try Runtime.runtime(profile,classPriors: [0.4,0.6],neutralScale: 1.5)
        let json = try Codec.encodeJSONObject(Codec.encodeClassifier(profile),maximumBytes: 65_536,maximumNesting: 16)
        let disk = try ReferenceDiskCodec(maximumPlaintextBytes: 65_536,maximumEncodedBytes: 131_072)
        let key = Data((0..<32).map { UInt8($0) }), iv = Data((0..<16).map { UInt8(32 + $0) })
        let envelope = try disk.encrypt(disk.compress(json),key: key,iv: iv)
        let restored = try disk.decompress(disk.decrypt(envelope,key: key))
        let object = try Codec.decodeJSONObject(restored,maximumBytes: 65_536,maximumNesting: 16)
        let decoded = try Codec.decodeClassifier(object,maximumElements: 4096)
        XCTAssertTrue(decoded.schemaAccepted)
        let after = try Runtime.runtime(XCTUnwrap(decoded.classifier),classPriors: [0.4,0.6],neutralScale: 1.5)
        for input in [[0.0,0],[2,4],[1,2]] {
            let a = try Runtime.infer(featureVector: input,runtime: before)
            let b = try Runtime.infer(featureVector: input,runtime: after)
            let direct = try Kernel.infer(featureVector: signature.preparation.selectedCoordinates.map { input[$0] },
                parameters: .init(pca: signature.pca,canonical: signature.canonical,canonicalClassCount: 2,
                    classes: signature.classes,classPriors: [0.4,0.6],neutralScale: 1.5))
            for (x,y) in zip(a.posterior,b.posterior) { XCTAssertEqual(x,y,accuracy: 1e-14) }
            for (x,y) in zip(a.classDensity,direct.classDensity) { XCTAssertEqual(x,y,accuracy: 1e-14) }
            XCTAssertEqual(a.canonicalFeatures,b.canonicalFeatures)
        }
        XCTAssertGreaterThan(try Runtime.infer(featureVector: [0,0],runtime: after).classDensity[0],
                             try Runtime.infer(featureVector: [0,0],runtime: after).classDensity[1])
    }
}
