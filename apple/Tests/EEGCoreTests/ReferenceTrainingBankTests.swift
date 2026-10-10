import XCTest
@testable import EEGCore

final class ReferenceTrainingBankTests: XCTestCase {
    private func append(_ bank: [ReferenceTrainingBank.ClassEntry], id: Int32 = 2,
                        rows: [[Double]] = [[1, 2, 3], [2, 4, 6]], times: [Double] = [12.75],
                        classes: Int = 4, components: Int = 3) throws -> [ReferenceTrainingBank.ClassEntry] {
        try ReferenceTrainingBank.addUpdate(featureRows: rows, updateTimes: times,
            classReferenceID: id, bank: bank, maximumEpochs: 16,
            maximumClasses: classes, maximumDistributionsPerClass: components)
    }
    func testAppendCreatesThenPreservesSeparateComponents() throws {
        let first = try append([])
        XCTAssertEqual(first[0].classReferenceID, 2)
        XCTAssertEqual(first[0].distributions[0].counts, [3, 3])
        XCTAssertEqual(first[0].distributions[0].mean, [2, 4])
        XCTAssertEqual(first[0].distributions[0].covariance, [[1, 2], [2, 4]])
        XCTAssertEqual(first[0].distributions[0].updateTime, 12)
        let next = try append(first, rows: [[10, 12], [20, 24]], times: [33, .nan])
        XCTAssertEqual(next[0].distributions.count, 2)
        XCTAssertEqual(next[0].distributions[0], first[0].distributions[0])
        XCTAssertEqual(next[0].distributions[1].mean, [11, 22])
        XCTAssertEqual(first[0].distributions.count, 1)
    }
    func testFirstMatchingClassAndNewClassOrder() throws {
        let first = try append([])
        let duplicates = first + first
        let next = try append(duplicates)
        XCTAssertEqual(next.map { $0.distributions.count }, [2, 1])
        let new = try append(next, id: 7)
        XCTAssertEqual(new.map(\.classReferenceID), [2, 2, 7])
    }
    func testEmptyUpdateDoesNotMutateOrInventComponent() throws {
        let bank = try append([])
        XCTAssertEqual(try append(bank, rows: []), bank)
        XCTAssertEqual(try append(bank, rows: [[], []]), bank)
        XCTAssertEqual(try append(bank, times: []), bank)
    }
    func testInvalidUpdatesAndCapacitiesFail() throws {
        let bank = try append([])
        for time in [Double.nan, -1, Double(UInt32.max) + 1] {
            XCTAssertThrowsError(try append(bank, times: [time]))
        }
        XCTAssertThrowsError(try append(bank, classes: 0))
        XCTAssertThrowsError(try append(bank, components: 1))
        XCTAssertThrowsError(try append(bank, id: 3, classes: 1))
        XCTAssertThrowsError(try append(bank, rows: [[1, 2], [3]]))
        XCTAssertEqual(bank[0].distributions.count, 1)
    }
    func testExponentialWeightsAreUnnormalizedWithNeutralOne() throws {
        let result = try ReferenceTrainingBank.classWeights(activeActionCount: 4,
            thresholdSlots: [1, 3, 5, 7], configuredWeightTable: [])
        for (actual, expected) in zip(result, [1, 0.01, 0.1, 1, 10]) {
            XCTAssertEqual(actual, expected, accuracy: 1e-12)
        }
        XCTAssertEqual(try ReferenceTrainingBank.classWeights(activeActionCount: 1,
            thresholdSlots: [5, 6, 7, 8], configuredWeightTable: [99]), [1, 1])
    }
    func testExplicitTableClampsSlotsWithoutGuessingValues() throws {
        let result = try ReferenceTrainingBank.classWeights(activeActionCount: 4,
            thresholdSlots: [.min, 1, 10, .max], configuredWeightTable: Array(1...10).map(Double.init))
        XCTAssertEqual(result, [1, 1, 1, 10, 10])
        XCTAssertThrowsError(try ReferenceTrainingBank.classWeights(activeActionCount: 0,
            thresholdSlots: [5, 5, 5, 5], configuredWeightTable: []))
        XCTAssertThrowsError(try ReferenceTrainingBank.classWeights(activeActionCount: 5,
            thresholdSlots: [5, 5, 5, 5], configuredWeightTable: []))
        XCTAssertThrowsError(try ReferenceTrainingBank.classWeights(activeActionCount: 1,
            thresholdSlots: [5], configuredWeightTable: []))
        XCTAssertThrowsError(try ReferenceTrainingBank.classWeights(activeActionCount: 1,
            thresholdSlots: [.max, 5, 5, 5], configuredWeightTable: []))
        XCTAssertThrowsError(try ReferenceTrainingBank.classWeights(activeActionCount: 1,
            thresholdSlots: [5, 5, 5, 5], configuredWeightTable: Array(repeating: .nan, count: 10)))
    }
}
