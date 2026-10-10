import XCTest
@testable import EEGCore

final class ReferenceSubscriptionCadenceTests: XCTestCase {
    typealias S = ReferenceSubscriptionCadence
    func testNonoverlappingOuterDeliveryFeedsOverlappingInnerManager() throws {
        var scheduler = try S(sampleRate: 128, windowSeconds: 0.125, stepSeconds: 0.125, startIndex: 0)
        let requests = try scheduler.process(startIndex: 0, endIndex: 512,
            isAlmostFull: false, maximumReads: 32, search: { _ in true })
        var manager = try ReferenceManagerCadence(configuration: .init(sampleRate: 128,
            windowSeconds: 1, stepSeconds: 0.125, selectedChannelCount: 1,
            maximumBufferedSamples: 512, maximumSamplesPerBlock: 16))
        var epochs = 0
        for request in requests {
            let block = (request.start..<request.endExclusive).map { Double($0) }
            let tick = try manager.detectorCall(selectedChannels: [block], control:
                .init(classifierEmpty: true, autoSamplingNeutral: false, trainingControl: 1))
            if let epoch = tick.featureInput { XCTAssertEqual(epoch[0].count,128); epochs += 1 }
        }
        XCTAssertEqual(requests.count,32)
        XCTAssertEqual(epochs,25)
        XCTAssertEqual(manager.bufferedSamples,112)
    }
    func testUpstreamDrainUsesProfileWindowStepNotWallTimer() throws {
        var scheduler = try S(sampleRate: 128, windowSeconds: 1, stepSeconds: 0.125, startIndex: 0)
        let reads = try scheduler.process(startIndex: 0, endIndex: 160, isAlmostFull: false,
                                         maximumReads: 3, search: { _ in true })
        XCTAssertEqual(reads.map(\.start), [0, 16, 32])
        XCTAssertEqual(reads.map(\.endExclusive), [128, 144, 160])
        XCTAssertEqual(scheduler.cursor, 48)
        XCTAssertTrue(reads.allSatisfy { !$0.mayClipSearch && $0.dropped == 0 })
        XCTAssertNil(try scheduler.read(startIndex: 0, endIndex: 160, force: false,
                                       isAlmostFull: false, search: { _ in XCTFail(); return true }))
    }
    func testDroppedCursorAndFailedSearchDoNotBecomeSuccessfulRead() throws {
        var scheduler = try S(sampleRate: 128, windowSeconds: 1, stepSeconds: 0.125, startIndex: 0)
        var observed: S.Request?
        XCTAssertNil(try scheduler.read(startIndex: 50, endIndex: 200, force: false,
                                        isAlmostFull: true, search: { observed = $0; return false }))
        XCTAssertEqual(observed?.dropped, 50)
        XCTAssertEqual(scheduler.cursor, 50)
        XCTAssertEqual(observed?.mayClipSearch, true)
        XCTAssertNotNil(try scheduler.read(startIndex: 50, endIndex: 200, force: false,
                                          isAlmostFull: true, search: { _ in true }))
        XCTAssertEqual(scheduler.cursor, 66)
    }
    func testBoundsTruncationAndCapacityFailureAreExplicit() throws {
        var scheduler = try S(sampleRate: 128, windowSeconds: 1.001, stepSeconds: 0.13, startIndex: 100)
        XCTAssertEqual(scheduler.windowSamples, 128)
        XCTAssertEqual(scheduler.stepSamples, 16)
        let request = try scheduler.read(startIndex: 0, endIndex: 300, force: false,
                                         isAlmostFull: true, search: { _ in true })
        XCTAssertEqual(request?.mayClipSearch, false) // equality at margin100
        XCTAssertThrowsError(try scheduler.process(startIndex: 0, endIndex: 1000,
            isAlmostFull: false, maximumReads: 1, search: { _ in true }))
        XCTAssertThrowsError(try S(sampleRate: 0, windowSeconds: 1, stepSeconds: 0.125, startIndex: 0))
        XCTAssertThrowsError(try S(sampleRate: 128, windowSeconds: 0.1, stepSeconds: 1, startIndex: 0))
    }
}
