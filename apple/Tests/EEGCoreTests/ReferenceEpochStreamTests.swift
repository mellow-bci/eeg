import XCTest
@testable import EEGCore

final class ReferenceEpochStreamTests: XCTestCase {
    private func stream(window: Double = 1, step: Double = 0.5) throws -> ReferenceEpochStream {
        try .init(sampleRate: 4, windowSeconds: window, stepSeconds: step, maximumBufferedSamples: 20)
    }

    func testOverlappingWindowsAndOneResultPerCall() throws {
        var value = try stream()
        try value.append([[0,1,2,3,4,5,6,7], [10,11,12,13,14,15,16,17]])
        XCTAssertEqual(value.nextWithRemoval(), [[0,1,2,3], [10,11,12,13]])
        XCTAssertEqual(value.bufferedSamples, 6)
        XCTAssertEqual(value.cursor, 0)
        XCTAssertEqual(value.nextWithRemoval(), [[2,3,4,5], [12,13,14,15]])
        XCTAssertEqual(value.bufferedSamples, 4)
        XCTAssertEqual(value.nextWithRemoval(), [[4,5,6,7], [14,15,16,17]])
        let previous = value.buffer
        XCTAssertNil(value.nextWithRemoval())
        XCTAssertEqual(value.buffer, previous)
    }

    func testNextCursorDoesNotRemoveAndRemovalUsesAdvancedCursor() throws {
        var value = try stream()
        try value.append([[0,1,2,3,4,5,6,7]])
        XCTAssertEqual(value.next(), [[0,1,2,3]])
        XCTAssertEqual(value.cursor, 2)
        XCTAssertEqual(value.bufferedSamples, 8)
        XCTAssertEqual(value.nextWithRemoval(), [[2,3,4,5]])
        XCTAssertEqual(value.buffer, [[4,5,6,7]])
        XCTAssertEqual(value.cursor, 0)
    }

    func testEqualWindowStepClearsBufferAndResetAllowsNewRows() throws {
        var value = try stream(step: 1)
        try value.append([[0,1,2,3]])
        XCTAssertEqual(value.nextWithRemoval(), [[0,1,2,3]])
        XCTAssertEqual(value.buffer, [])
        try value.append([[4,5]])
        XCTAssertNil(value.next())
        value.reset()
        try value.append([[1,2,3,4], [5,6,7,8]])
        XCTAssertEqual(value.nextWithRemoval(), [[1,2,3,4], [5,6,7,8]])
    }

    func testTruncationAppendAndTransactionalFailure() throws {
        var value = try stream(window: 1.2, step: 0.7)
        XCTAssertEqual(value.windowSamples, 4)
        XCTAssertEqual(value.stepSamples, 2)
        try value.append([[0,1]])
        XCTAssertNil(value.nextWithRemoval())
        try value.append([[2,3]])
        XCTAssertEqual(value.nextWithRemoval(), [[0,1,2,3]])
        let original = value.buffer
        XCTAssertThrowsError(try value.append([[1], [2]]))
        XCTAssertThrowsError(try value.append([[.nan]]))
        XCTAssertThrowsError(try value.append([Array(repeating: 0, count: 20)]))
        XCTAssertEqual(value.buffer, original)
    }

    func testInvalidTimingDoesNotGuessUnsignedConversion() throws {
        for (window, step) in [(0.0, 1.0), (1, 0), (1, 2), (.infinity, 1), (1, .nan), (1, 0.1)] {
            XCTAssertThrowsError(try stream(window: window, step: step))
        }
    }
}
