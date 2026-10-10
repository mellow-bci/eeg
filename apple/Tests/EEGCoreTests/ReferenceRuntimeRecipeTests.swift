import XCTest
@testable import EEGCore

final class ReferenceRuntimeRecipeTests: XCTestCase {
    typealias R = ReferenceRuntimeRecipe
    private var channels: [UInt32] { [92,54] }
    private func profile(mode: Int32 = 1) -> R.ConvertedProfile {
        .init(version: "20180327",values: [
            "cognitiv-bands": .matrix(.init(rows: 2,columns: 4,elements: [4,7,8,12,50,51,52,53])),
            "cognitiv-isBandPower": .integer(mode),
            "cognitiv-winSizeInSec": .floating(0.5),
            "cognitiv-stepSizeInSec": .floating(0.0625),
        ])
    }
    func testMatchingVersionUsesFirstRowAndExactPowerModePredicate() throws {
        let result = try R.resolve(profile(),headsetTypeID: 9,inputChannels: channels,maximumFeatures: 100)
        XCTAssertFalse(result.usedDefaultProfile)
        XCTAssertEqual(result.inputIndices,[1,0])
        XCTAssertEqual(result.recipe.bands.map(\.lowerHz),[4,8])
        XCTAssertEqual(result.recipe.bands.map(\.upperHz),[7,12])
        XCTAssertEqual(result.features.count,4)
        let stream = try result.makeStream(sampleRate: 128,maximumBufferedSamples: 256)
        XCTAssertEqual(stream.windowSamples,64)
        XCTAssertEqual(stream.stepSamples,8)
        let ratio = try R.resolve(profile(mode: 2),headsetTypeID: 9,inputChannels: channels,maximumFeatures: 100)
        XCTAssertFalse(ratio.recipe.isBandPower)
        XCTAssertEqual(ratio.features.count,5)
    }
    func testVersionFallbackIsWholeRecipeAndMatchingMissingDoesNotInventDefault() throws {
        var old = profile()
        old.version = "old"
        let result = try R.resolve(old,headsetTypeID: 9,inputChannels: channels,maximumFeatures: 100)
        XCTAssertTrue(result.usedDefaultProfile)
        XCTAssertEqual(result.recipe.windowSeconds,1)
        XCTAssertEqual(result.recipe.bands.count,7)
        old.version = nil
        XCTAssertTrue(try R.resolve(old,headsetTypeID: 9,inputChannels: channels,maximumFeatures: 100).usedDefaultProfile)
        var matching = profile()
        matching.values.removeValue(forKey: "cognitiv-winSizeInSec")
        XCTAssertThrowsError(try R.resolve(matching,headsetTypeID: 9,inputChannels: channels,maximumFeatures: 100)) {
            XCTAssertEqual($0 as? R.Failure,.missingConvertedValue("cognitiv-winSizeInSec"))
        }
        matching = profile()
        matching.values["cognitiv-isBandPower"] = .floating(1)
        XCTAssertThrowsError(try R.resolve(matching,headsetTypeID: 9,inputChannels: channels,maximumFeatures: 100))
    }
    func testReinitializationMakesFreshFilterAndStreamAndRejectsOddBands() throws {
        let result = try R.resolve(profile(),headsetTypeID: 9,inputChannels: channels,maximumFeatures: 100)
        var stream = try result.makeStream(sampleRate: 128,maximumBufferedSamples: 256)
        try stream.append([[Double](repeating: 2,count: 64)])
        XCTAssertNotNil(stream.nextWithRemoval())
        XCTAssertEqual(try result.makeStream(sampleRate: 128,maximumBufferedSamples: 256).bufferedSamples,0)
        var first = try result.makeFilter(maximumChannels: 2,maximumSamplesPerBlock: 128)
        _ = try first.apply([[10,20,30]])
        let continued = try first.apply([[40]])
        var fresh = try result.makeFilter(maximumChannels: 2,maximumSamplesPerBlock: 128)
        let restarted = try fresh.apply([[40]])
        XCTAssertNotEqual(continued,restarted)
        var odd = profile()
        odd.values["cognitiv-bands"] = .matrix(.init(rows: 1,columns: 3,elements: [4,7,8]))
        XCTAssertThrowsError(try R.resolve(odd,headsetTypeID: 9,inputChannels: channels,maximumFeatures: 100)) {
            XCTAssertEqual($0 as? R.Failure,.unsupportedBands)
        }
    }
}
