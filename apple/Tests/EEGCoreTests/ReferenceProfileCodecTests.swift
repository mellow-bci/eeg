import XCTest
@testable import EEGCore

final class ReferenceProfileCodecTests: XCTestCase {
    private typealias V = ReferenceProfileCodec.Value
    private func object(_ rows: Double, _ columns: Double, _ values: [V]) -> [String: V] {
        ["rows": .number(rows), "cols": .number(columns), "elements": .array(values)]
    }
    func testExactSchemaAndWrongTypesAreDistinctFromEmptyMatrix() throws {
        let empty = try ReferenceProfileCodec.decodeMatrix(object(0,0,[]), maximumElements: 0)
        XCTAssertTrue(empty.schemaAccepted)
        var extra = object(0,0,[]); extra["other"] = .null
        XCTAssertFalse(try ReferenceProfileCodec.decodeMatrix(extra, maximumElements: 0).schemaAccepted)
        var wrong = object(0,0,[]); wrong["rows"] = .bool(false)
        XCTAssertFalse(try ReferenceProfileCodec.decodeMatrix(wrong, maximumElements: 0).schemaAccepted)
        XCTAssertFalse(try ReferenceProfileCodec.decodeMatrix([:], maximumElements: 0).schemaAccepted)
    }
    func testLinearImportShortArrayPadsZerosAndNonNumbersBecomeZero() throws {
        let result = try ReferenceProfileCodec.decodeMatrix(
            object(2,3,[.number(4),.bool(true),.string("9"),.number(-2)]), maximumElements: 6)
        XCTAssertTrue(result.schemaAccepted)
        XCTAssertEqual(result.matrix.elements,[4,0,0,-2,0,0])
        XCTAssertEqual(result.matrix.rows,2)
        XCTAssertEqual(result.matrix.columns,3)
    }
    func testExceptionalShapesAndFiniteDomainAreExplicitErrors() {
        for value in [object(1,0,[]),object(1,1,[]),object(1,1,[.number(1),.number(2)]),
                      object(-1,1,[.number(1)]),object(1.5,1,[.number(1)]),
                      object(1,1,[.number(.nan)])] {
            XCTAssertThrowsError(try ReferenceProfileCodec.decodeMatrix(value, maximumElements: 4))
        }
        XCTAssertThrowsError(try ReferenceProfileCodec.decodeMatrix(object(2,3,[.number(1)]),maximumElements: 5))
    }
    func testUnsignedBridgeAcceptsEitherVectorOrientationAndRejectsMatrix() throws {
        for shape in [(1.0,3.0),(3.0,1.0)] {
            let matrix = try ReferenceProfileCodec.decodeMatrix(
                object(shape.0,shape.1,[.number(8),.number(2),.number(7)]),maximumElements: 3).matrix
            XCTAssertEqual(try ReferenceProfileCodec.unsignedVector(matrix),[8,2,7])
        }
        let matrix = try ReferenceProfileCodec.decodeMatrix(object(2,2,[.number(1)]),maximumElements: 4).matrix
        XCTAssertThrowsError(try ReferenceProfileCodec.unsignedVector(matrix))
    }
    func testCountSignExtensionIsNotLosslessUnsignedJSONRoundTrip() {
        XCTAssertEqual(ReferenceProfileCodec.storedClassifierCount(decodedQtInt: 0),0)
        XCTAssertEqual(ReferenceProfileCodec.storedClassifierCount(decodedQtInt: .max),2_147_483_647)
        XCTAssertEqual(ReferenceProfileCodec.storedClassifierCount(decodedQtInt: -1),UInt64.max)
        XCTAssertEqual(ReferenceProfileCodec.storedClassifierCount(decodedQtInt: .min),18_446_744_071_562_067_968)
    }
    private func classifier() -> ReferenceProfileCodec.Classifier {
        let matrix = ReferenceProfileCodec.Matrix(rows: 1, columns: 2, elements: [2,5])
        return .init(weightMeanVariances: [.init(weight: matrix, mean: matrix, variances: [matrix])],
            classRefIDs: [7,2], uniqueFeatureIndices: [8,3], coeff: matrix, pcMeans: matrix,
            eigenvec: matrix, meanTot: matrix, channelInUse: matrix, numOfValidFeatures: 2, useCount: 4)
    }
    func testFullTypedEnvelopeRoundTripPreservesOrderWithoutAssertingTrainingValidity() throws {
        let input = classifier()
        let object = try ReferenceProfileCodec.encodeClassifier(input)
        let result = try ReferenceProfileCodec.decodeClassifier(object, maximumElements: 8)
        XCTAssertTrue(result.schemaAccepted)
        XCTAssertEqual(result.classifier,input)
        // One WMV and two IDs are accepted by the converter; no inferred count matching.
        XCTAssertEqual(result.classifier?.weightMeanVariances.count,1)
        XCTAssertEqual(result.classifier?.classRefIDs.count,2)
    }
    func testNestedRejectedSchemaRetainsOtherFieldsWithFalseFlag() throws {
        var object = try ReferenceProfileCodec.encodeClassifier(classifier())
        object["coeff"] = .object([:])
        object["classRefIDs"] = .array([.string("7"),.number(-3)])
        let result = try ReferenceProfileCodec.decodeClassifier(object, maximumElements: 8)
        XCTAssertFalse(result.schemaAccepted)
        XCTAssertEqual(result.classifier?.coeff,.empty)
        XCTAssertEqual(result.classifier?.classRefIDs,[0,-3])
        object["useCount"] = .string("4")
        XCTAssertNil(try ReferenceProfileCodec.decodeClassifier(object,maximumElements: 8).classifier)
    }
    func testIntegerAndCountDomainDoNotSilentlyGuessQtOverflowRules() throws {
        var object = try ReferenceProfileCodec.encodeClassifier(classifier())
        object["useCount"] = .number(2_147_483_648)
        XCTAssertThrowsError(try ReferenceProfileCodec.decodeClassifier(object,maximumElements: 8))
        object["useCount"] = .number(1.5)
        XCTAssertThrowsError(try ReferenceProfileCodec.decodeClassifier(object,maximumElements: 8))
    }
    func testNonSquareRowMajorMappingMatchesTwoIndexAccessorEquation() throws {
        let rows = [[1.0,2,3],[4,5,6]]
        let matrix = try ReferenceProfileCodec.Matrix.fromRows(rows)
        XCTAssertEqual(matrix.elements,[1,2,3,4,5,6])
        XCTAssertEqual(try matrix.rowValues(),rows)
        XCTAssertEqual(matrix.elements[1 * matrix.columns + 2],6)
    }
    func testJSONBridgePreservesBooleanNumberNullAndEnforcesCallerLimits() throws {
        let object: [String: V] = ["bool":.bool(true),"number":.number(1),"null":.null,
            "nested":.array([.object(["value":.string("EEG")])])]
        let bytes = try ReferenceProfileCodec.encodeJSONObject(object,maximumBytes: 512,maximumNesting: 5)
        XCTAssertEqual(try ReferenceProfileCodec.decodeJSONObject(bytes,maximumBytes: 512,maximumNesting: 5),object)
        XCTAssertThrowsError(try ReferenceProfileCodec.encodeJSONObject(object,maximumBytes: 1,maximumNesting: 5))
        XCTAssertThrowsError(try ReferenceProfileCodec.decodeJSONObject(bytes,maximumBytes: 1,maximumNesting: 5))
        XCTAssertThrowsError(try ReferenceProfileCodec.decodeJSONObject(bytes,maximumBytes: 512,maximumNesting: 1))
    }
    func testOwnClassifierJSONGzipEncryptionRoundTripWithCallerKey() throws {
        let input = classifier()
        let object = try ReferenceProfileCodec.encodeClassifier(input)
        let bytes = try ReferenceProfileCodec.encodeJSONObject(object,maximumBytes: 16_384,maximumNesting: 16)
        let disk = try ReferenceDiskCodec(maximumPlaintextBytes: 16_384,maximumEncodedBytes: 32_768)
        let key = Data((0..<32).map(UInt8.init)), iv = Data((0..<16).map { UInt8(16 + $0) })
        let envelope = try disk.encrypt(disk.compress(bytes),key: key,iv: iv)
        let restored = try disk.decompress(disk.decrypt(envelope,key: key))
        XCTAssertEqual(restored,bytes)
        let decodedObject = try ReferenceProfileCodec.decodeJSONObject(restored,maximumBytes: 16_384,maximumNesting: 16)
        let decoded = try ReferenceProfileCodec.decodeClassifier(decodedObject,maximumElements: 16)
        XCTAssertTrue(decoded.schemaAccepted)
        XCTAssertEqual(decoded.classifier,input)
    }
    private func gaussian(_ time: UInt32) -> ReferenceGaussianPooling.Distribution {
        .init(counts: [12,15],mean: [2,-3],covariance: [[4,1],[1,9]],updateTime: time)
    }
    func testGaussianAlgebraOwnEncryptedRoundTripPreservesSignedTimestampBits() throws {
        let input = ReferenceTrainingBank.ClassEntry(classReferenceID: -3,
            distributions: [gaussian(123),gaussian(UInt32.max)])
        let object = try ReferenceProfileCodec.encodeGaussianAlgebra(input)
        let bytes = try ReferenceProfileCodec.encodeJSONObject(object,maximumBytes: 16_384,maximumNesting: 16)
        let disk = try ReferenceDiskCodec(maximumPlaintextBytes: 16_384,maximumEncodedBytes: 32_768)
        let key = Data((0..<32).map { UInt8($0) }), iv = Data(repeating: 7,count: 16)
        let encrypted = try disk.encrypt(disk.compress(bytes),key: key,iv: iv)
        let plain = try disk.decompress(disk.decrypt(encrypted,key: key))
        let decodedObject = try ReferenceProfileCodec.decodeJSONObject(plain,maximumBytes: 16_384,maximumNesting: 16)
        let result = try ReferenceProfileCodec.decodeGaussianAlgebra(decodedObject,maximumElements: 16)
        XCTAssertTrue(result.schemaAccepted)
        XCTAssertEqual(result.rejectedDistributionIndices,[])
        XCTAssertEqual(result.entry,input)
        XCTAssertEqual(try ReferenceProfileCodec.encodeGaussianData(gaussian(UInt32.max))["updateTime"],.number(-1))
    }
    func testGaussianAlgebraOuterFlagStaysTrueWhenNestedDataAreOmitted() throws {
        let valid = try ReferenceProfileCodec.encodeGaussianData(gaussian(4))
        var invalid = valid; invalid["average"] = .object([:])
        let object: [String: V] = ["classRefId":.number(8),
            "gaussianData":.array([.object(valid),.object(invalid),.null,.object(valid)])]
        let decoded = try ReferenceProfileCodec.decodeGaussianAlgebra(object,maximumElements: 16)
        XCTAssertTrue(decoded.schemaAccepted)
        XCTAssertEqual(decoded.rejectedDistributionIndices,[1,2])
        XCTAssertEqual(decoded.entry?.distributions,[gaussian(4),gaussian(4)])
    }
    func testGaussianSchemaRejectionAndUnsupportedMatrixDomainAreDistinct() throws {
        var object = try ReferenceProfileCodec.encodeGaussianData(gaussian(4))
        object["extra"] = .null
        XCTAssertFalse(try ReferenceProfileCodec.decodeGaussianData(object,maximumElements: 16).schemaAccepted)
        object.removeValue(forKey: "extra")
        object["numberOfEpochs"] = .object(self.object(2,1,[.number(12),.number(15)]))
        XCTAssertThrowsError(try ReferenceProfileCodec.decodeGaussianData(object,maximumElements: 16))
        let outer: [String: V] = ["classRefId":.string("8"),"gaussianData":.array([])]
        XCTAssertNil(try ReferenceProfileCodec.decodeGaussianAlgebra(outer,maximumElements: 16).entry)
    }
    func testProfileDispatchUsesShapeNotPropertyNameAndExposesOmissions() throws {
        let bank = ReferenceTrainingBank.ClassEntry(classReferenceID: 7,distributions: [gaussian(12)])
        let object: [String: V] = ["arbitrary-classifier-key":.object(try ReferenceProfileCodec.encodeClassifier(classifier())),
            "bank":.object(try ReferenceProfileCodec.encodeGaussianAlgebra(bank)),
            "matrix":.object(self.object(1,1,[.number(9)])),"name":.string("independent"),"score":.number(0.3),
            "boolean":.bool(true),"unknown":.object([:])]
        let result = try ReferenceProfileCodec.decodeProfile(object,maximumElements: 16)
        XCTAssertEqual(result.properties["arbitrary-classifier-key"],.classifier(classifier()))
        XCTAssertEqual(result.properties["bank"],.gaussianAlgebra(bank))
        XCTAssertEqual(result.properties["name"],.string("independent"))
        XCTAssertEqual(result.omittedKeys,["boolean","unknown"])
    }
}
