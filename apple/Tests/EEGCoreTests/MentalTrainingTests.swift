import Foundation
import XCTest
@testable import EEGCore

final class MentalTrainingTests: XCTestCase {
    private struct Fixture: Decodable {
        let records: [EEGTrainingRecord]
        let fitted: EEGMentalScoringParameters
    }
    private func fixture() throws -> Fixture {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appendingPathComponent("Fixtures/spectrum/mental-training.json")))
    }
    func testFittedComponentsGaussiansAndScoresMatchPython() throws {
        let input = try fixture()
        let result = try EEGMentalTraining.fit(input.records, participantID: "participant")
        XCTAssertEqual(result.classes, input.fitted.classes)
        XCTAssertEqual(result.selected, input.fitted.selected)
        XCTAssertEqual(result.components.count, 8)
        let actual = result.components.flatMap { $0 } + result.gaussians.flatMap { $0.mean + $0.variance + [$0.distance_limit] }
        let expected = input.fitted.components.flatMap { $0 } + input.fitted.gaussians.flatMap { $0.mean + $0.variance + [$0.distance_limit] }
        XCTAssertEqual(actual.count, expected.count)
        for (a, b) in zip(actual, expected) { XCTAssertEqual(a, b, accuracy: 1e-8) }
        for record in input.records {
            let native = try EEGMentalScoring.score(values: record.values, parameters: result)
            let python = try EEGMentalScoring.score(values: record.values, parameters: input.fitted)
            for (a, b) in zip(native.uncalibratedScores, python.uncalibratedScores) { XCTAssertEqual(a, b, accuracy: 1e-8) }
            XCTAssertEqual(native.candidateLabel, python.candidateLabel)
        }
    }
    func testWideMatrixAndDegenerateBasisRemainOrthonormal() throws {
        for matrix in [[[1.0, 0, 0, 0], [0, 2, 0, 0]], [[0.0, 0, 0], [0, 0, 0]]] {
            let rows = try EEGMentalTraining.principalComponents(matrix, count: 2)
            for i in 0..<2 {
                for j in 0..<2 {
                    let dot = zip(rows[i], rows[j]).reduce(0.0) { $0 + $1.0 * $1.1 }
                    XCTAssertEqual(dot, i == j ? 1 : 0, accuracy: 1e-12)
                }
            }
        }
    }
    func testInvalidMatricesRejected() {
        for matrix in [[], [[1.0], [1, 2]], [[Double.nan]], [[Double.infinity]]] {
            XCTAssertThrowsError(try EEGMentalTraining.principalComponents(matrix, count: 1))
        }
        XCTAssertThrowsError(try EEGMentalTraining.principalComponents([[1.0]], count: 2))
    }
}
