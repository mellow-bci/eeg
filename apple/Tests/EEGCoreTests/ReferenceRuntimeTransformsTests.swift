import XCTest
@testable import EEGCore

final class ReferenceRuntimeTransformsTests: XCTestCase {
    func testNonzeroTrainingCenterAndZeroRuntimeCanonicalCenter() throws {
        let scatter = try ReferenceCanonicalScatter.construct(classes: [
            .init(counts: [8], mean: [10], covariance: [[2]]),
            .init(counts: [8], mean: [14], covariance: [[2]])
        ], pcaBasis: [[2]], maximumClasses: 2)
        let result = try ReferenceRuntimeTransforms.assemble(pcaCenter: [12], pcaBasis: [[2]],
                                                             scatter: scatter, canonicalBasis: [[3]])
        XCTAssertEqual(result.canonical.mean, [0])
        XCTAssertEqual(result.finalClasses[0].mean, [-12])
        XCTAssertEqual(result.finalClasses[1].mean, [12])
        XCTAssertEqual(result.finalClasses[0].covariance, [[72]])
        XCTAssertEqual(result.finalClasses[0].weight, 1)
        XCTAssertEqual(result.trainingRuntimeCenterDifference, [0])
        XCTAssertEqual(try ReferenceRuntimeTransforms.project([10], using: result, classCount: 2), [-12])
    }
    func testHeterogeneousCountMismatchIsExposedNotCorrected() throws {
        let scatter = try ReferenceCanonicalScatter.construct(classes: [
            .init(counts: [6, 20], mean: [0, 0], covariance: [[1, 0], [0, 1]]),
            .init(counts: [12, 30], mean: [3, 10], covariance: [[1, 0], [0, 1]])
        ], pcaBasis: [[1, 0], [0, 1]], maximumClasses: 2)
        let result = try ReferenceRuntimeTransforms.assemble(pcaCenter: [2, 6], pcaBasis: [[1, 0], [0, 1]],
                                                             scatter: scatter, canonicalBasis: [[0], [1]])
        XCTAssertEqual(result.trainingRuntimeCenterDifference[1], -2.0 / 3, accuracy: 1e-12)
        XCTAssertEqual(result.finalClasses[1].mean[0], 10.0 / 3, accuracy: 1e-12)
        XCTAssertEqual(try ReferenceRuntimeTransforms.project([3, 10], using: result, classCount: 2), [4])
    }
    func testRejectsIncompatibleBasisAndCenter() throws {
        let scatter = try ReferenceCanonicalScatter.construct(classes: [
            .init(counts: [8], mean: [0], covariance: [[1]]),
            .init(counts: [8], mean: [1], covariance: [[1]])
        ], pcaBasis: [[1]], maximumClasses: 2)
        XCTAssertThrowsError(try ReferenceRuntimeTransforms.assemble(pcaCenter: [], pcaBasis: [[1]], scatter: scatter, canonicalBasis: [[1]]))
        XCTAssertThrowsError(try ReferenceRuntimeTransforms.assemble(pcaCenter: [0], pcaBasis: [[1]], scatter: scatter, canonicalBasis: [[0]]))
    }
}
