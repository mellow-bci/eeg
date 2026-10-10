import XCTest
@testable import EEGCore

final class ReferenceBartlettSelectionTests: XCTestCase {
    func testAnalyticProductsStatisticsAndDegreesOfFreedom() throws {
        let d = try ReferenceBartlettSelection.diagnostics(ascendingRoots: [0, 1, 3], classCount: 3, effectiveEpochCount: 100)
        XCTAssertEqual(d.reverseReciprocalProducts, [0.125, 0.5])
        XCTAssertEqual(d.multiplier, -96)
        XCTAssertEqual(d.degreesOfFreedom, [6, 2])
        XCTAssertEqual(d.statistics[0], 96 * log(8), accuracy: 1e-12)
        XCTAssertEqual(d.statistics[1], 96 * log(2), accuracy: 1e-12)
    }

    func testUsesAllRootsBeforeClassRankTruncation() throws {
        let d = try ReferenceBartlettSelection.diagnostics(ascendingRoots: [1, 2, 3, 4], classCount: 2, effectiveEpochCount: 20)
        XCTAssertEqual(d.reverseReciprocalProducts.count, 1)
        XCTAssertEqual(d.reverseReciprocalProducts[0], 1.0 / 120)
        XCTAssertEqual(d.degreesOfFreedom, [4])
        XCTAssertEqual(d.multiplier, -16)
    }

    func testZeroRootsAndZeroMultiplierRemainDiagnosticValues() throws {
        let d = try ReferenceBartlettSelection.diagnostics(ascendingRoots: [0, 0], classCount: 3, effectiveEpochCount: 3.5)
        XCTAssertEqual(d.reverseReciprocalProducts, [1, 1])
        XCTAssertTrue(d.statistics.allSatisfy { $0 == 0 })
        XCTAssertEqual(d.degreesOfFreedom, [4, 1])
    }

    func testRejectsInvalidOrderingDomainAndNonfiniteValues() {
        for roots in [[2.0, 1], [-1, 1], [Double.nan], [Double.infinity], []] {
            XCTAssertThrowsError(try ReferenceBartlettSelection.diagnostics(ascendingRoots: roots, classCount: 2, effectiveEpochCount: 20))
        }
        XCTAssertThrowsError(try ReferenceBartlettSelection.diagnostics(ascendingRoots: [0], classCount: 1, effectiveEpochCount: 20))
        XCTAssertThrowsError(try ReferenceBartlettSelection.diagnostics(ascendingRoots: [0], classCount: 2, effectiveEpochCount: .nan))
    }

    func testOverflowIsExplicitInsteadOfMockRank() {
        XCTAssertThrowsError(try ReferenceBartlettSelection.diagnostics(ascendingRoots: [1e200, 1e200], classCount: 3, effectiveEpochCount: 20)) { error in
            XCTAssertEqual(error as? ReferenceBartlettSelection.InputError, .arithmeticOverflow)
        }
    }
}
