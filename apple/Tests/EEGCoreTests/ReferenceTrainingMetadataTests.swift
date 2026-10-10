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
    func testInstalledQtScalarOracleWithoutRelaxingDefaultStoragePolicy() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        for filename in ["oracle.tsv","oracle-boundaries.tsv","oracle-json.tsv"] {
            let file = root.appendingPathComponent("evidence/mental-command-reference/metadata-coercion-continuation-20261011/" + filename)
            for line in try String(contentsOf: file,encoding: .utf8).split(separator: "\n") {
                let fields = line.split(separator: "\t",omittingEmptySubsequences: false)
                guard fields.count >= 3 else { return XCTFail("Malformed oracle vector") }
                let value: V
                switch fields[0] {
                case "string": value = .string(String(fields[1]))
                case "number": value = .number(try XCTUnwrap(Double(fields[1])))
                case "bool": value = .bool(fields[1] == "true")
                case "null": value = .null
                case "array", "object":
                    let collection: V = fields[0] == "array" ? .array([]) : .object([:])
                    XCTAssertThrowsError(try Metadata.decode(["deleted":collection],booleanConversion: .qtBounded))
                    continue
                default: return XCTFail("Unsupported oracle vector")
                }
                if case .number(let number) = value, abs(number) > 9_007_199_254_740_991 {
                    XCTAssertThrowsError(try Metadata.decode(["deleted": value],booleanConversion: .qtBounded))
                    continue
                }
                let decoded = try Metadata.decode(["deleted":value,"loaded":value],booleanConversion: .qtBounded)
                XCTAssertEqual(decoded.deleted,fields[2] == "true",String(line))
                XCTAssertEqual(decoded.loaded,decoded.deleted)
                if case .bool = value { } else if case .null = value { } else { XCTAssertThrowsError(try Metadata.decode(["deleted":value])) }
            }
        }
    }
    func testUnsupportedQtComparisonTypesAndNonfiniteNumbersReject() {
        for value in [V.array([]),.object([:]),.string("é"),.string(String(repeating:"x",count:4097)),.number(.nan),.number(.infinity),.number(-.infinity)] {
            XCTAssertThrowsError(try Metadata.decode(["loaded":value],booleanConversion: .qtBounded))
        }
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
