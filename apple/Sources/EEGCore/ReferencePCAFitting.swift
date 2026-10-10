import Foundation

/// Comparison-only runPCA/princompMultiClass with finite low-epoch clipping.
/// The shared finite symmetric PSD eigensolver retains zero roots. LAPACK,
/// sign conventions and rejection of negative roots are our support choices.
enum ReferencePCAFitting {
    enum InputError: Error, Equatable {
        case invalidClasses
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
        let eigenbasis = try ReferenceTrainingEdgeCases.psdEigenbasis(covariance: pooled.covariance)
        let clipped = try ReferencePCALowEpoch.apply(counts: pooled.counts,
            descendingEigenvalues: eigenbasis.eigenvalues, basis: eigenbasis.basis)
        let indices = try ReferenceTrainingEdgeCases.pcaSelectedIndices(
            descendingEigenvalues: clipped.eigenvalues, classCount: classes.count)
        let transform: ReferenceGaussianPipeline.CenteredTransform? = indices.isEmpty ? nil :
            .init(mean: pooled.mean, basis: clipped.basis.map { row in indices.map { row[$0] } })
        return Fit(pooled: pooled, eigenvalues: clipped.eigenvalues,
                   selectedIndices: indices, transform: transform)
    }
}
