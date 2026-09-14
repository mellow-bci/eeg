import XCTest
@testable import EEGCore

final class PoissonBoundTests: XCTestCase {
    func testMatchesScipyChiSquareOracle() throws {
        // scipy.stats.chi2.ppf(.95, 2*(count+1))/2, generated with SciPy 1.13.1.
        let cases: [(Int, Double)] = [(0,2.99573227355399),(1,4.743864518390577),
            (2,6.295793621871988),(10,16.962219235721903),(15,23.097129760139243),
            (16,24.301183683647082),(100,118.07927278209706),(1000,1053.6031221333008),
            (10000,10166.060136127071),(1000000,1001646.4227676168)]
        for (count, expected) in cases {
            let actual = try XCTUnwrap(EEGPoissonBound.upper95(count: count))
            XCTAssertEqual(actual, expected, accuracy: max(1e-10, expected * 1e-10))
            XCTAssertGreaterThan(actual, Double(count))
        }
    }
    func testNoExposureAndCarryInNeverProduceRateBound() throws {
        var exposure = EEGConditionExposure()
        XCTAssertNil(exposure.poissonUpper95PerHour)
        exposure.eligibleSeconds = 3600
        XCTAssertEqual(try XCTUnwrap(exposure.poissonUpper95PerHour), -log(0.05), accuracy: 1e-12)
        exposure.carryInCandidates = 1
        XCTAssertNil(exposure.poissonUpper95PerHour)
        XCTAssertNil(EEGPoissonBound.upper95(count: -1))
        XCTAssertNil(EEGPoissonBound.upper95(count: Int.max))
    }
}
