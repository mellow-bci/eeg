import XCTest
@testable import EEGCore

final class ReferenceManagerCadenceTests: XCTestCase {
    typealias M = ReferenceManagerCadence
    private func config(rate: Int = 16) -> M.Configuration {
        .init(sampleRate: rate, windowSeconds: 1, stepSeconds: 0.5,
              selectedChannelCount: 1, maximumBufferedSamples: 128, maximumSamplesPerBlock: 64)
    }
    private let enabled = M.Control(classifierEmpty: false, autoSamplingNeutral: false, trainingControl: 0)
    func testSingleRemovalPerCallAndExplicitEmptyTicks() throws {
        var manager = try M(configuration: config())
        let block = [(0..<48).map { sin(Double($0) * 0.4) }]
        var result = try manager.detectorCall(selectedChannels: block, control: enabled)
        XCTAssertEqual(result.consumedEpoch?.first?.count, 16)
        var epochs = 1
        for _ in 0..<4 {
            result = try manager.detectorCall(selectedChannels: [], control: enabled)
            XCTAssertEqual(result.route, .extractFeatures); epochs += 1
        }
        XCTAssertEqual(epochs, 5)
        XCTAssertEqual(try manager.detectorCall(selectedChannels: [], control: enabled).route, .waiting)
    }
    func testFeatureGateConsumesEpochWithoutPretendingToClassify() throws {
        for (classifierEmpty, autoSampling, trainingControl, expected) in [
            (true, false, 0, M.Route.consumedWithoutFeatures),
            (true, false, 2, .consumedWithoutFeatures),
            (true, false, 1, .extractFeatures),
            (true, true, 0, .extractFeatures),
            (false, false, 0, .extractFeatures)] {
            var manager = try M(configuration: config())
            let result = try manager.detectorCall(selectedChannels: [Array(repeating: 2, count: 16)],
                control: .init(classifierEmpty: classifierEmpty, autoSamplingNeutral: autoSampling, trainingControl: trainingControl))
            XCTAssertEqual(result.route, expected)
            XCTAssertNotNil(result.consumedEpoch)
            XCTAssertEqual(result.featureInput != nil, expected == .extractFeatures)
            XCTAssertEqual(try manager.detectorCall(selectedChannels: [], control: enabled).route, .waiting)
        }
    }
    func testStopRetainsFilterButInitializationReplacesItAndPropagatesRate() throws {
        var manager = try M(configuration: config())
        var filter = try ReferenceDeployedFilter.deployed(maximumChannels: 1, maximumSamplesPerBlock: 64)
        let first = [(0..<16).map(Double.init)]
        _ = try manager.detectorCall(selectedChannels: first, control: enabled)
        _ = try filter.apply(first)
        XCTAssertEqual(manager.stop(), .init(resetTrainingState: true, clearBackgroundMatrix: true, inputFilterReset: false))
        XCTAssertEqual(manager.bufferedSamples, 0)
        let second = [Array(repeating: 0.0, count: 16)]
        let expected = try filter.apply(second)
        XCTAssertEqual(try manager.detectorCall(selectedChannels: second, control: enabled).filteredBlock, expected)
        try manager.initialize(configuration: config(rate: 32))
        XCTAssertEqual(manager.windowSamples, 32); XCTAssertEqual(manager.stepSamples, 16)
        let fresh = try manager.detectorCall(selectedChannels: second, control: enabled)
        XCTAssertEqual(fresh.route, .waiting)
        XCTAssertEqual(fresh.filteredBlock, second)
    }
}
