import Foundation

/// Comparison-only normal-support branch of runPCA/princompMultiClass.
/// The vendor low-epoch clipping and singular eigensolver branches are explicit
/// unsupported states. LAPACK/sign conventions remain our documented choices.
enum ReferencePCAFitting {
    enum InputError: Error, Equatable {
        case invalidClasses, lowEpochClippingUnsupported
    }
    struct Fit {
        let pooled: ReferenceGaussianPooling.Distribution
        let eigenvalues: [Double]
        let selectedIndices: [Int]
        /// Nil mirrors runPCA's empty-selection abort; no minimum is invented.
        let transform: ReferenceGaussianPipeline.CenteredTransform?
    }

    /// Inputs are already the single selected Gaussian for each class. The
    /// input order is significant for pooling metadata and unsupported cells.
    static func fit(classes: [ReferenceGaussianPooling.Distribution]) throws -> Fit {
        guard classes.count >= 2 else { throw InputError.invalidClasses }
        var pooled: ReferenceGaussianPooling.Distribution?
        for value in classes {
            pooled = try ReferenceGaussianPooling.combine(pooled, value, useFirstUpdateTime: false)
        }
        guard let pooled else { throw InputError.invalidClasses }
        let dimension = pooled.mean.count
        // 0x100b48798..48850 counts all n[f]<=p. If all satisfy that relation,
        // 48854..488cc clips eigenpairs using a scratch count. Keep that branch
        // separate instead of replacing it with an inferred effective rank.
        guard pooled.counts.contains(where: { $0 > Double(dimension) }) else {
            throw InputError.lowEpochClippingUnsupported
        }
        let eigenbasis = try ReferenceGaussianPipeline.covarianceEigenbasis(pooled.covariance)
        let indices = try ReferenceCanonicalTraining.pcaSelectedIndices(
            descendingEigenvalues: eigenbasis.eigenvalues, classCount: classes.count)
        let transform: ReferenceGaussianPipeline.CenteredTransform? = indices.isEmpty ? nil :
            .init(mean: pooled.mean, basis: eigenbasis.basis.map { row in indices.map { row[$0] } })
        return Fit(pooled: pooled, eigenvalues: eigenbasis.eigenvalues,
                   selectedIndices: indices, transform: transform)
    }
}
