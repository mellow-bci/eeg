import Foundation
import XCTest
@testable import EEGCore

final class MentalScoringTests: XCTestCase {
    private struct Case: Decodable { let values: [Double]; let scores: [Double]; let label: String; let outside: Bool }
    private struct Fixture: Decodable { let parameters: EEGMentalScoringParameters; let cases: [Case] }
    private func fixture() throws -> Fixture {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appendingPathComponent("Fixtures/spectrum/mental-scoring.json")))
    }
    func testNativeTransformsAndGaussianScoresMatchPython() throws {
        let f = try fixture()
        for c in f.cases {
            let actual = try EEGMentalScoring.score(values: c.values, parameters: f.parameters)
            XCTAssertEqual(actual.candidateLabel, c.label)
            XCTAssertEqual(actual.outsideTrainingDistribution, c.outside)
            for (a, e) in zip(actual.uncalibratedScores, c.scores) { XCTAssertEqual(a, e, accuracy: 1e-10) }
        }
    }
    func testInvalidAndExtremeFeaturesReject() throws {
        let f = try fixture()
        for values in [[Double](), [Double](repeating: .nan, count: 70), [Double](repeating: 1e308, count: 70)] {
            XCTAssertThrowsError(try EEGMentalScoring.score(values: values, parameters: f.parameters))
        }
    }
}
