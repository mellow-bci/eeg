import XCTest
@testable import EEGCore

final class ReferenceFeatureSelectionTests: XCTestCase {
    private func stats(_ mean: [Double], _ variance: [Double], _ count: [Double]) -> ReferenceFeatureSelection.ClassStatistics {
        .init(mean: mean, variance: variance, epochCounts: count)
    }

    func testAsymmetricStandardizationAndWorstCompetitor() throws {
        let result = try ReferenceFeatureSelection.select([
            stats([0, 0], [1, 4], [20, 20]),
            stats([3, 8], [9, 1], [20, 20]),
            stats([6, 2], [4, 4], [20, 20])
        ])
        XCTAssertEqual(result.scoresByClass[0][0], 3 / (1 + ReferenceFeatureSelection.denominatorEpsilon), accuracy: 1e-14)
        XCTAssertEqual(result.scoresByClass[0][1], 2 / (2 + ReferenceFeatureSelection.denominatorEpsilon), accuracy: 1e-14)
        XCTAssertEqual(result.scoresByClass[1][0], 3 / (3 + ReferenceFeatureSelection.denominatorEpsilon), accuracy: 1e-14)
        XCTAssertEqual(result.rankedCoordinatesByClass[0], [0, 1])
        XCTAssertEqual(result.rankedCoordinatesByClass[1], [1, 0])
        XCTAssertEqual(result.selectedCoordinates, [0, 1])
    }

    func testCountBoundaryAndUnmaskedBudgetNumerator() throws {
        let width = 10
        let result = try ReferenceFeatureSelection.coordinateBudget(epochCounts: [
            Array(repeating: 20, count: width), Array(repeating: 19, count: width)
        ])
        // ceil(sqrt(2*(20+19)/1))=9, not ceil(sqrt(2*20))=7.
        XCTAssertEqual(result, 9)
        XCTAssertThrowsError(try ReferenceFeatureSelection.select([
            stats(Array(repeating: 0, count: width), Array(repeating: 1, count: width), Array(repeating: 20, count: width)),
            stats((1...width).map(Double.init), Array(repeating: 1, count: width), Array(repeating: 19, count: width))
        ])) { XCTAssertEqual($0 as? ReferenceFeatureSelection.InputError, .ambiguousCutoffTie) }
    }

    func testBudgetSelectionUnionAndInclusiveTwenty() throws {
        let width = 10
        let result = try ReferenceFeatureSelection.select([
            stats(Array(repeating: 0, count: width), Array(repeating: 1, count: width), Array(repeating: 20, count: width)),
            stats((1...width).map(Double.init), Array(repeating: 1, count: width), Array(repeating: 20, count: width))
        ])
        XCTAssertEqual(result.perClassBudget, 7)
        XCTAssertEqual(result.selectedCoordinates, Array(3..<10))
        XCTAssertEqual(result.rankedCoordinatesByClass[0], Array((0..<10).reversed()))
    }

    func testInsufficientCountsAndInvalidStatisticsAreExplicit() {
        XCTAssertThrowsError(try ReferenceFeatureSelection.select([stats([0], [1], [19]), stats([1], [1], [19])])) {
            XCTAssertEqual($0 as? ReferenceFeatureSelection.InputError, .insufficientEpochs)
        }
        XCTAssertThrowsError(try ReferenceFeatureSelection.select([stats([0], [-1], [20]), stats([1], [1], [20])]))
        XCTAssertThrowsError(try ReferenceFeatureSelection.select([stats([0], [1], [20])]))
    }

    func testClassSpecificSelectionsAreUnioned() throws {
        let width = 10
        let delta = (1...width).map(Double.init)
        let secondVariance = delta.enumerated().map { i, value in pow(value / Double(width - i), 2) }
        let result = try ReferenceFeatureSelection.select([
            stats(Array(repeating: 0, count: width), Array(repeating: 1, count: width), Array(repeating: 20, count: width)),
            stats(delta, secondVariance, Array(repeating: 20, count: width))
        ])
        XCTAssertEqual(result.perClassBudget, 7)
        XCTAssertEqual(Array(result.rankedCoordinatesByClass[0].prefix(7)), Array((3..<10).reversed()))
        XCTAssertEqual(Array(result.rankedCoordinatesByClass[1].prefix(7)), Array(0..<7))
        XCTAssertEqual(result.selectedCoordinates, Array(0..<10))
    }

    func testZeroVarianceUsesTracedEpsilonRatherThanInventedFloor() throws {
        let result = try ReferenceFeatureSelection.select([stats([0], [0], [20]), stats([1], [4], [20])])
        XCTAssertEqual(result.scoresByClass[0][0], 1 / ReferenceFeatureSelection.denominatorEpsilon)
        XCTAssertEqual(result.scoresByClass[1][0], 1 / (2 + ReferenceFeatureSelection.denominatorEpsilon))
    }
}
