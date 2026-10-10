import XCTest
@testable import EEGCore
final class ReferenceDeployedFilterTests: XCTestCase {
    private func filter(_ b: [Double] = [1, 0, 0], _ a: [Double] = [1, 0, 0]) throws -> ReferenceDeployedFilter {
        try ReferenceDeployedFilter(numerator: b, feedback: a, maximumChannels: 4, maximumSamplesPerBlock: 64)
    }
    func testInitialHistoriesRepeatFirstSampleAndA0IsIgnored() throws {
        var f = try filter([1, 2, 3], [999, 4, 5])
        XCTAssertEqual(try f.apply([[2, 3]]), [[-6, 27]])
    }
    func testSplitBlocksIncludingSingleSampleMatchWholeBlock() throws {
        let b = [0.97554449992839098, -1.9510888162127069, 0.97554449992839098]
        let a = [1.0, -1.9504906552523591, 0.95168716081713]
        let xs = [8.0, 9, 12, 4, -3, 8, 2]
        var whole = try filter(b, a), split = try filter(b, a)
        let expected = try whole.apply([xs])[0]
        var actual: [Double] = []
        for value in xs { actual += try split.apply([[value]])[0] }
        XCTAssertEqual(actual, expected)
    }
    func testRowsIndependentAndRowCountChangeReinitializesAll() throws {
        var f = try filter([1, 1, 1])
        XCTAssertEqual(try f.apply([[2, 3], [10, 11]]), [[6, 7], [30, 31]])
        XCTAssertEqual(try f.apply([[20]]), [[60]])
        f.reset()
        XCTAssertEqual(try f.apply([[4]]), [[12]])
    }
    func testInvalidInputDoesNotMutateAndLimitsAreExplicit() throws {
        var f = try filter([1, 1, 1])
        _ = try f.apply([[2]])
        XCTAssertThrowsError(try f.apply([[]]))
        XCTAssertThrowsError(try f.apply([[Double.nan]]))
        XCTAssertThrowsError(try f.apply([[1], [2, 3]]))
        XCTAssertThrowsError(try f.apply(Array(repeating: [1], count: 5)))
        XCTAssertThrowsError(try f.apply([Array(repeating: 1, count: 65)]))
        XCTAssertEqual(try f.apply([[3]]), [[7]])
    }
    func testOverflowRejectsWithoutPublishingState() throws {
        var f = try filter([Double.greatestFiniteMagnitude, 0, 0])
        XCTAssertThrowsError(try f.apply([[2]]))
        XCTAssertEqual(try f.apply([[0]]), [[0]])
    }
}
