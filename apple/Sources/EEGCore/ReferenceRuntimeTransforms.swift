import Foundation

/// Comparison-only assembly for buildSignatureFromPCA's resolved centering path.
/// Explicit fitted bases and class statistics remain prerequisites, not vendor assets.
enum ReferenceRuntimeTransforms {
    struct Assembly {
        let pca: ReferenceGaussianPipeline.CenteredTransform
        let canonical: ReferenceGaussianPipeline.CenteredTransform
        let finalClasses: [ReferenceGaussianPipeline.Component]
        /// Original pooled PCA center projected into PCA coordinates minus the
        /// independently pooled projected class center. Diagnostic, never corrected.
        let trainingRuntimeCenterDifference: [Double]
    }
    enum AssemblyError: Error { case invalidShape }

    static func assemble(pcaCenter: [Double], pcaBasis: [[Double]],
                         scatter: ReferenceCanonicalScatter.Construction,
                         canonicalBasis: [[Double]]) throws -> Assembly {
        let size = scatter.pooled.mean.count
        guard (1...70).contains(size), pcaCenter.count == pcaBasis.count,
              pcaBasis.allSatisfy({ $0.count == size }), canonicalBasis.count == size,
              let outputs = canonicalBasis.first?.count, (1...70).contains(outputs),
              canonicalBasis.allSatisfy({ $0.count == outputs }),
              scatter.projectedClasses.count >= 2 else { throw AssemblyError.invalidShape }
        let pca = ReferenceGaussianPipeline.CenteredTransform(mean: pcaCenter, basis: pcaBasis)
        let canonical = ReferenceGaussianPipeline.CenteredTransform(
            mean: Array(repeating: 0, count: size), basis: canonicalBasis)
        let projectedPCACenter = try ReferenceGaussianPipeline.transform(pcaCenter,
            using: .init(mean: Array(repeating: 0, count: pcaCenter.count), basis: pcaBasis))
        let difference = zip(projectedPCACenter, scatter.pooled.mean).map { $0.0 - $0.1 }
        let components = try scatter.projectedClasses.map { value in
            let projected = try ReferenceGaussianPipeline.projectDistribution(
                .init(weight: 1, mean: value.mean, covariance: value.covariance), basis: canonicalBasis)
            // manova1Cov final means subtract the pooled projected mean before
            // multiplication; do not put that same center in runtime canonical.
            let mean = try ReferenceGaussianPipeline.transform(value.mean,
                using: .init(mean: scatter.pooled.mean, basis: canonicalBasis))
            let result = ReferenceGaussianPipeline.Component(weight: 1, mean: mean,
                                                               covariance: projected.covariance)
            _ = try ReferenceGaussianPipeline.gaussianDensity(mean, component: result)
            return result
        }
        return .init(pca: pca, canonical: canonical, finalClasses: components,
                     trainingRuntimeCenterDifference: difference)
    }

    static func project(_ selectedFeatures: [Double], using assembly: Assembly,
                        classCount: Int) throws -> [Double] {
        let pca = try ReferenceGaussianPipeline.transform(selectedFeatures, using: assembly.pca)
        return try ReferenceGaussianPipeline.canonicalTransform(pca, using: assembly.canonical,
                                                                classCount: classCount)
    }
}
