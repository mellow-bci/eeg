import XCTest
@testable import EEGCore

final class SessionResamplingTests: XCTestCase {
    private func metric(_ observed: Int, _ scored: Int, declared: Int? = nil) -> EEGLabeledEvaluation.TrialMetric {
        .init(declaredTrials: declared ?? scored, scoredTrials: scored, observedTrials: observed,
              trialsWithoutEligibleExposure: 0, declaredSeconds: Double(scored) * 12, eligibleSeconds: Double(scored) * 12)
    }
    func testPairedSessionResamplingMatchesIndependentNumpyQuantiles() throws {
        let rows = ["A": metric(1,2), "B": metric(2,8), "C": metric(7,10), "D": metric(18,20)]
        let options = EEGSessionResampling.Options(iterations: 1000, seed: 42)
        let result = try EEGSessionResampling.run(rows, options: options)
        XCTAssertEqual(result.status, "exploratory_only")
        XCTAssertEqual(try XCTUnwrap(result.lower), 0.3, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(result.upper), 61.0/70, accuracy: 1e-12)
        XCTAssertEqual(result, try EEGSessionResampling.run(rows, options: options))
        XCTAssertEqual(result.sessionIDs, ["A","B","C","D"])
        XCTAssertEqual(result.options, options)
    }
    func testUncertaintyIsUnavailableForMissingOrDegenerateEvidence() throws {
        let cases: [([String: EEGLabeledEvaluation.TrialMetric], String)] = [
            ([:], "insufficient_sessions"), (["A":metric(1,2)], "insufficient_sessions"),
            (["A":metric(1,2),"B":metric(2,2,declared:3)], "incomplete_cue_evidence"),
            (["A":metric(0,2),"B":metric(0,10)], "no_observed_session_variation"),
            (["A":metric(2,2),"B":metric(10,10)], "no_observed_session_variation")]
        for (rows,status) in cases {
            let value = try EEGSessionResampling.run(rows, options: .init())
            XCTAssertEqual(value.status,status);XCTAssertNil(value.lower);XCTAssertNil(value.upper)
        }
    }
    func testInvalidSettingsAndCountsAreRejected() throws {
        for options in [EEGSessionResampling.Options(iterations: 1), .init(centralMass: 0), .init(centralMass: 1), .init(centralMass: .nan)] {
            XCTAssertThrowsError(try EEGSessionResampling.run([:],options: options))
        }
        XCTAssertThrowsError(try EEGSessionResampling.run(["A":metric(3,2)],options:.init()))
    }
    func testLinearQuantileInterpolation() {
        XCTAssertEqual(EEGSessionResampling.quantile([0,1,4,10],0.25),0.75)
        XCTAssertEqual(EEGSessionResampling.quantile([0,1,4,10],0.975),9.55,accuracy:1e-12)
    }
    func testCancelledAnalysisDoesNotReturnRange() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try EEGSessionResampling.run(["A": self.metric(1,2), "B": self.metric(2,3)],options:.init())
                return false
            } catch is CancellationError { return true }
            catch { return false }
        }
        let cancelled = await task.value
        XCTAssertTrue(cancelled)
    }

}
