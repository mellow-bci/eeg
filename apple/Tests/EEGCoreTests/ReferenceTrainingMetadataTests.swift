import XCTest
@testable import EEGCore

final class ReferenceTrainingMetadataTests: XCTestCase {
    typealias Metadata = ReferenceTrainingMetadata
    typealias V = ReferenceProfileCodec.Value
    func testObservedKeysTypesAndUnknownWireFieldsRoundTripWithoutNormalization() throws {
        let object: [String: V] = ["uuid":.string("own-1"),"name":.string("Own comparison"),
            "ownerId":.string("local"),"deleted":.bool(false),"loaded":.bool(true),
            "originalUuid":.string(""),"originalProfileURL":.string(""),
            "createdDatetime":.string("not-a-date"),"modifiedDatetime":.string("2026-10-11T12:13:14.123+05:30"),
            "eegChannels":.array([.string("AF3"),.string("AF3"),.string("unmapped")]),
            "own-extra":.object(["schemaVersion":.number(1)])]
        let metadata = try Metadata.decode(object)
        XCTAssertTrue(metadata.stringFieldsWithoutStringInput.isEmpty)
        XCTAssertEqual(metadata.eegChannels,["AF3","AF3","unmapped"])
        XCTAssertEqual(Metadata.encode(metadata),object)
        try Metadata.requireIdentity(metadata,profileID: "own-1")
        XCTAssertThrowsError(try Metadata.requireIdentity(metadata,profileID: "other"))
    }
    func testMissingAndNonStringInputsExposeEmptyProjectionAndProvenance() throws {
        let metadata = try Metadata.decode(["uuid":.number(3),"loaded":.null])
        XCTAssertEqual(metadata.uuid,"")
        XCTAssertFalse(metadata.loaded)
        XCTAssertFalse(metadata.deleted)
        XCTAssertNil(metadata.eegChannels)
        XCTAssertEqual(metadata.stringFieldsWithoutStringInput,Set([
            "uuid","name","ownerId","originalUuid","originalProfileURL","createdDatetime","modifiedDatetime"]))
        let emitted = Metadata.encode(metadata)
        XCTAssertEqual(emitted["uuid"],.string(""))
        XCTAssertNil(emitted["eegChannels"])
    }
    func testEmptyChannelArrayIsPreservedAndUntracedCoercionsReject() throws {
        XCTAssertEqual(try Metadata.decode(["eegChannels":.array([])]).eegChannels,[])
        for value in [V.number(1),.string("true"),.array([])] {
            XCTAssertThrowsError(try Metadata.decode(["deleted":value]))
        }
        XCTAssertThrowsError(try Metadata.decode(["eegChannels":.array([.number(1)])]))
        XCTAssertThrowsError(try Metadata.decode(["eegChannels":.string("AF3")]))
        XCTAssertEqual(Metadata.attributesIdentity(uuid: "own-1"),["uuid":.string("own-1")])
    }
}
