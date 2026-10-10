import XCTest
@testable import EEGCore

final class ReferenceDeployedRecipeTests: XCTestCase {
    typealias R = ReferenceDeployedRecipe
    typealias F = ReferenceDeployedFeatures.Feature
    func testDefaultProfileConstantsRemainExplicitAndOverrideable() throws {
        var recipe = R.defaultProfile
        XCTAssertEqual(recipe.windowSeconds,1)
        XCTAssertEqual(recipe.stepSeconds,0.125)
        XCTAssertTrue(recipe.isBandPower)
        XCTAssertEqual(recipe.bands.map(\.lowerHz),[4,8,13,18,23,27,31])
        XCTAssertEqual(recipe.bands.map(\.upperHz),[7,12,17,22,26,30,57])
        let stream = try ReferenceEpochStream(sampleRate: 128,windowSeconds: recipe.windowSeconds,
                                             stepSeconds: recipe.stepSeconds,maximumBufferedSamples: 256)
        XCTAssertEqual(stream.windowSamples,128)
        XCTAssertEqual(stream.stepSamples,16)
        recipe.stepSeconds = 0.25
        XCTAssertEqual(R.defaultProfile.stepSeconds,0.125)
    }
    func testPowerOrderAndHandDerivedTwoByTwoRatioOrder() throws {
        let powers: [F] = [.power(.init(row: 0,band: 0)),.power(.init(row: 0,band: 1)),
                           .power(.init(row: 1,band: 0)),.power(.init(row: 1,band: 1))]
        XCTAssertEqual(try R.features(channelCount: 2,bandCount: 2,isBandPower: true,maximumFeatures: 4),powers)
        let ratios: [F] = [
            .ratio(numerator: .init(row: 0,band: 0),denominator: .init(row: 0,band: 1)),
            .ratio(numerator: .init(row: 0,band: 0),denominator: .init(row: 1,band: 0)),
            .ratio(numerator: .init(row: 0,band: 0),denominator: .init(row: 1,band: 1)),
            .ratio(numerator: .init(row: 0,band: 1),denominator: .init(row: 1,band: 1)),
            .ratio(numerator: .init(row: 1,band: 0),denominator: .init(row: 1,band: 1))]
        XCTAssertEqual(try R.features(channelCount: 2,bandCount: 2,isBandPower: false,maximumFeatures: 5),ratios)
        // Flattened upper-triangle would have six, incorrectly adding (0,1)/(1,0).
        let values = try ReferenceDeployedFeatures.extract(channelBands: [[1,10],[100,1000]],features: ratios)
        XCTAssertEqual(values,[-10,-20,-30,-20,-10])
        XCTAssertThrowsError(try R.features(channelCount: 2,bandCount: 2,isBandPower: false,maximumFeatures: 4))
        XCTAssertEqual(try R.features(channelCount: 1,bandCount: 1,isBandPower: false,maximumFeatures: 0),[])
    }
    func testActualNumericTargetDispatchAndInputRowMapping() throws {
        XCTAssertEqual(R.targetChannels(forHeadsetTypeID: 1),[40,54,72,92,106])
        XCTAssertEqual(R.targetChannels(forHeadsetTypeID: 2),R.targetChannels(forHeadsetTypeID: 1))
        XCTAssertEqual(R.targetChannels(forHeadsetTypeID: 9),[54,92])
        XCTAssertEqual(R.targetChannels(forHeadsetTypeID: 10),[54,92])
        XCTAssertEqual(R.targetChannels(forHeadsetTypeID: 3),ReferenceChannelMetadata.defaultTrainingChannels)
        XCTAssertEqual(R.targetChannels(forHeadsetTypeID: -1),ReferenceChannelMetadata.defaultTrainingChannels)
        XCTAssertEqual(try R.inputIndices(targetChannels: [92,54,92],inputChannels: [54,92,54]),[1,0,1])
        XCTAssertThrowsError(try R.inputIndices(targetChannels: [40],inputChannels: [54,92]))
    }
}
