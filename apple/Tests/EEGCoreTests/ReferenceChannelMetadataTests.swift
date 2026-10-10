import XCTest
@testable import EEGCore

final class ReferenceChannelMetadataTests: XCTestCase {
    typealias C = ReferenceChannelMetadata

    func testActualInitializerVocabularyAndCaseSensitiveReverseLookup() {
        XCTAssertEqual(C.databaseNames.count,179)
        XCTAssertEqual(Set(C.databaseNames).count,179)
        for id in UInt32(0)...UInt32(178) {
            XCTAssertEqual(C.databaseID(for: C.databaseName(for: id)),id)
        }
        XCTAssertEqual(C.databaseID(for: "FP1"),117)
        XCTAssertEqual(C.databaseID(for: "Fp1"),39)
        XCTAssertEqual(C.databaseID(for: "Fpz"),38)
        XCTAssertEqual(C.databaseID(for: "fp1"),0)
        XCTAssertEqual(C.databaseName(for: 140),"COUNTER")
        XCTAssertEqual(C.databaseName(for: 174),"ACCY")
    }

    func testMissingAndEmptyChannelsUseExactDefaultAndOmitExport() {
        let absent = C.normalizeTrainingChannels(nil)
        XCTAssertEqual(absent,C.normalizeTrainingChannels([]))
        XCTAssertTrue(absent.usesDefaultList)
        XCTAssertNil(absent.exportedNames)
        XCTAssertEqual(absent.channelIDs.map { C.databaseName(for: $0) },
                       ["AF3","F7","F3","FC5","T7","P7","O1","O2","P8","T8","FC6","F4","F8","AF4"])
    }

    func testUnknownStringAndUnknownEnumHaveDifferentFallbacksWithoutRawRewrite() throws {
        let raw = try ReferenceTrainingMetadata.decode(["eegChannels":.array([
            .string("AF3"),.string("unknown"),.string("AF3"),.string("UNUSED"),.string("")])])
        let normalized = C.normalizeTrainingChannels(raw.eegChannels)
        XCTAssertEqual(normalized.channelIDs,[40,0,40,163,0])
        XCTAssertEqual(normalized.exportedNames,["AF3","LA","AF3","UNUSED","LA"])
        XCTAssertFalse(normalized.usesDefaultList)
        XCTAssertEqual(C.databaseName(for: UInt32.max),"UNUSED")
        XCTAssertEqual(raw.eegChannels,["AF3","unknown","AF3","UNUSED",""])
        XCTAssertEqual(ReferenceTrainingMetadata.encode(raw)["eegChannels"],.array([
            .string("AF3"),.string("unknown"),.string("AF3"),.string("UNUSED"),.string("")]))
    }
}
