import XCTest
@testable import EEGCore

/// Analytic composition check, not a recorded Cortex comparison or EEG experiment.
final class ReferenceFittedWorkflowTests: XCTestCase {
    func testPooledFitThroughRuntimeCentersAndGaussianScoring() throws {
        try assertFittedWorkflow(covariance: [[4, 0, 0], [0, 2, 0], [0, 0, 1]])
    }
    func testSingularClassCovarianceFitsAndScoresInPositiveVarianceSubspace() throws {
        try assertFittedWorkflow(covariance: [[4, 0, 0], [0, 2, 0], [0, 0, 0]])
    }
    private func assertFittedWorkflow(covariance: [[Double]]) throws {
        let classes: [ReferenceGaussianPooling.Distribution] = [
            .init(counts: [12, 12, 12], mean: [2, 4, 6], covariance: covariance, updateTime: 10),
            .init(counts: [12, 12, 12], mean: [4, 4, 6], covariance: covariance, updateTime: 20)]
        let pca = try ReferencePCAFitting.fit(classes: classes)
        let transform = try XCTUnwrap(pca.transform)
        let scatter = try ReferenceCanonicalScatter.construct(classes: classes.map {
            .init(counts: $0.counts, mean: $0.mean, covariance: $0.covariance)
        }, pcaBasis: transform.basis, maximumClasses: 2)
        let canonical = try ReferenceCanonicalTraining.fit(within: scatter.withinScatter,
            between: scatter.betweenScatter, residualDegreesOfFreedom: scatter.residualDegreesOfFreedom,
            directions: 1)
        let assembly = try ReferenceRuntimeTransforms.assemble(pcaCenter: transform.mean,
            pcaBasis: transform.basis, scatter: scatter, canonicalBasis: canonical.basis)
        XCTAssertTrue(assembly.trainingRuntimeCenterDifference.allSatisfy { abs($0) < 1e-12 })
        let parameters = ReferenceGaussianPipeline.Parameters(pca: assembly.pca,
            canonical: assembly.canonical, canonicalClassCount: 2,
            classes: assembly.finalClasses.map { .init(components: [$0]) },
            classPriors: [1, 1], neutralScale: 1) // Explicit analytic fixture settings.
        for index in classes.indices {
            let result = try ReferenceGaussianPipeline.infer(featureVector: classes[index].mean,
                parameters: parameters)
            XCTAssertEqual(result.canonicalFeatures[0], assembly.finalClasses[index].mean[0], accuracy: 1e-12)
            XCTAssertGreaterThan(result.classDensity[index], result.classDensity[1-index])
            XCTAssertEqual(result.posterior.count, 3)
            XCTAssertEqual(result.posterior.reduce(0,+), 1, accuracy: 1e-12)
        }
    }
}
