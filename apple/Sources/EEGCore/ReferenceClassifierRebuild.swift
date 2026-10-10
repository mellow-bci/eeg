import Foundation

/// Comparison-only ordinary builder used by the error-set detection miss.
/// No noisy-channel mask is guessed: the traced builder has no noisy-ID input.
enum ReferenceClassifierRebuild {
    typealias Signature = ReferenceSignatureTraining.Signature
    enum Route: Equatable { case inactiveTrainingAction, untrainedClass, cached, fitted, fitRejected }
    struct Result {
        let signature: Signature?
        let route: Route
        let failureDescription: String?
    }
    enum Failure: Error { case mismatchedClassCount, emptyPCASelection }

    /// Explicit limits are independent resource/retry policies. This fits using
    /// our body-derived kernels and own inputs; it supplies no trained assets.
    static func fit(_ classes: [ReferenceSignatureTraining.ClassAlgebra],
                    featureChannelMetadata: [[Double]], maximumClasses: Int,
                    maximumCanonicalDiagonalAdditions: Int) throws -> Signature {
        try ReferenceSignatureTraining.run(classes, featureChannelMetadata: featureChannelMetadata) { preparation in
            let pca = try ReferencePCAFitting.fit(classes: preparation.selectedClasses)
            guard let transform = pca.transform else { throw Failure.emptyPCASelection }
            let scatter = try ReferenceCanonicalScatter.construct(classes: preparation.selectedClasses.map {
                .init(counts: $0.counts, mean: $0.mean, covariance: $0.covariance)
            }, pcaBasis: transform.basis, maximumClasses: maximumClasses)
            let canonical = try ReferenceTrainingEdgeCases.boundedCanonical(
                within: scatter.withinScatter, between: scatter.betweenScatter,
                residualDegreesOfFreedom: scatter.residualDegreesOfFreedom,
                directions: preparation.selectedClasses.count - 1,
                maximumDiagonalAdditions: maximumCanonicalDiagonalAdditions)
            let runtime = try ReferenceRuntimeTransforms.assemble(pcaCenter: transform.mean,
                pcaBasis: transform.basis, scatter: scatter, canonicalBasis: canonical.fit.basis)
            return .init(pca: runtime.pca, canonical: runtime.canonical,
                classes: runtime.finalClasses.map { .init(mean: $0.mean, covariance: $0.covariance) })
        }
    }

    /// appendNewData=false path only. Loads feature slots before Gaussian slots;
    /// cached reuse bypasses both loads. This path never saves new training data.
    /// Loader callbacks must access actual typed storage, not fabricate success.
    static func run(actions: [Int32], trainingAction: Int32,
                    featureChannelMetadata: [[Double]], maximumClasses: Int,
                    maximumCanonicalDiagonalAdditions: Int,
                    cache: inout ReferenceClassifierCache<Signature>,
                    loadFeatureData: () throws -> Void,
                    loadGaussianData: () throws -> [ReferenceTrainingBank.ClassEntry]) throws -> Result {
        guard actions.contains(trainingAction) else {
            return .init(signature: nil, route: .inactiveTrainingAction, failureDescription: nil)
        }
        if let cached = cache.recordReuse(actions) {
            return .init(signature: cached.payload, route: .cached, failureDescription: nil)
        }
        try loadFeatureData()
        let classes = try loadGaussianData()
        guard classes.count == actions.count else { throw Failure.mismatchedClassCount }
        guard classes.allSatisfy({ !$0.distributions.isEmpty }) else {
            return .init(signature: nil, route: .untrainedClass, failureDescription: nil)
        }
        let signature: Signature
        do {
            signature = try fit(classes.map {
                .init(classReferenceID: $0.classReferenceID, distributions: $0.distributions)
            }, featureChannelMetadata: featureChannelMetadata, maximumClasses: maximumClasses,
                maximumCanonicalDiagonalAdditions: maximumCanonicalDiagonalAdditions)
        } catch {
            return .init(signature: nil, route: .fitRejected, failureDescription: String(describing: error))
        }
        try cache.put(actions, entry: .init(actions: actions, payload: signature, reuseCount: 0))
        return .init(signature: signature, route: .fitted, failureDescription: nil)
    }
}
