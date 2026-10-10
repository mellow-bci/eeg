import Foundation

/// Comparison-only ordinary builder used by the error-set detection miss.
/// No noisy-channel mask is guessed: the traced builder has no noisy-ID input.
enum ReferenceClassifierRebuild {
    typealias Signature = ReferenceSignatureTraining.Signature
    enum Route: Equatable { case noNewData, inactiveTrainingAction, untrainedClass, cached, fitted, fitRejected }
    struct Result {
        let signature: Signature?
        let route: Route
        let failureDescription: String?
    }
    enum Failure: Error { case mismatchedClassCount, mismatchedPendingCount, emptyPCASelection }

    struct TrainingLimits {
        let maximumCells: Int
        let maximumEpochs: Int
        let maximumClasses: Int
        let maximumDistributionsPerClass: Int
        let storedMaximumEpochs: Int32
        let storedMaximumDistributions: Int
        let maximumCanonicalDiagonalAdditions: Int
    }
    struct Acceptance {
        let build: Result
        /// Profile-property save result, not an asynchronous disk durability receipt.
        let outcome: ReferenceNeutralTraining.FitResult
    }

    /// onTrainingAccepted composition. Storage and profile-update operations
    /// remain explicit; a successful property save never invents durable disk IO.
    static func acceptTraining(actions: [Int32], trainingAction: Int32,
                               pendingFeatures: [[[Double]]], pendingTimestamps: [[[Double]]],
                               featureChannelMetadata: [[Double]], limits: TrainingLimits,
                               store: inout ReferenceTrainingDatabase.Store,
                               cache: inout ReferenceClassifierCache<Signature>, classifier: inout Signature?,
                               saveClassifier: (Signature?) -> Bool, clearErrors: () -> Void,
                               updateTrainingCount: () -> Void, updateActions: () -> Void,
                               updateBrainMapIfEligible: () -> Void, unlockSettings: () -> Void) throws -> Acceptance {
        let result = try append(actions: actions, trainingAction: trainingAction,
            pendingFeatures: pendingFeatures, pendingTimestamps: pendingTimestamps,
            featureChannelMetadata: featureChannelMetadata, limits: limits, store: &store, cache: &cache)
        var next = classifier
        let outcome = ReferenceTrainingPersistence.accept(build: {
            guard let signature = result.signature else { return false }
            next = signature
            return true
        }, clearClassifier: { next = nil }, save: { saveClassifier(next) }, clearErrors: clearErrors,
            updateTrainingCount: updateTrainingCount, updateActions: updateActions,
            updateBrainMapIfEligible: updateBrainMapIfEligible, unlockSettings: unlockSettings)
        classifier = next
        return Acceptance(build: result, outcome: outcome)
    }

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
        return try finish(classes: classes, actions: actions, featureChannelMetadata: featureChannelMetadata,
            maximumClasses: maximumClasses, maximumCanonicalDiagonalAdditions: maximumCanonicalDiagonalAdditions,
            cache: &cache)
    }

    /// True-append builder: pending primary/timestamp matrices are independent
    /// ordered column joins. Training-data writes precede fitting, even when
    /// another class remains untrained. They are not a durable model save.
    static func append(actions: [Int32], trainingAction: Int32,
                       pendingFeatures: [[[Double]]], pendingTimestamps: [[[Double]]],
                       featureChannelMetadata: [[Double]], limits: TrainingLimits,
                       store: inout ReferenceTrainingDatabase.Store,
                       cache: inout ReferenceClassifierCache<Signature>) throws -> Result {
        guard pendingFeatures.count == pendingTimestamps.count else { throw Failure.mismatchedPendingCount }
        guard !pendingFeatures.isEmpty else {
            return .init(signature: nil, route: .noNewData, failureDescription: nil)
        }
        guard let actionIndex = actions.firstIndex(of: trainingAction) else {
            return .init(signature: nil, route: .inactiveTrainingAction, failureDescription: nil)
        }
        if cache.isEnabled { cache.removeDirtyClassifier(trainingAction) }
        if let cached = cache.recordReuse(actions) {
            return .init(signature: cached.payload, route: .cached, failureDescription: nil)
        }
        _ = try ReferenceTrainingDatabase.loadFeatures(classIDs: actions, store: store)
        let loaded = try ReferenceTrainingDatabase.loadGaussian(classIDs: actions, store: store)
        let features = try ReferenceTrainingEpochAssembly.combineColumns(pendingFeatures,
            maximumCells: limits.maximumCells)
        let times = try ReferenceTrainingEpochAssembly.combineColumns(pendingTimestamps,
            maximumCells: limits.maximumCells)
        // Matrix::operator()(0) supplies the first timestamp; the existing
        // bounded addUpdate helper consumes only that first value.
        let classes = try ReferenceTrainingBank.addUpdate(featureRows: features, updateTimes: times.first ?? [],
            classReferenceID: trainingAction, bank: loaded, maximumEpochs: limits.maximumEpochs,
            maximumClasses: limits.maximumClasses,
            maximumDistributionsPerClass: limits.maximumDistributionsPerClass)
        _ = try ReferenceTrainingDatabase.saveFeatures(classIDs: [trainingAction], features: [features],
            timestamps: [times], maximumEpochs: limits.storedMaximumEpochs, store: &store)
        _ = try ReferenceTrainingDatabase.saveGaussian(classIDs: [trainingAction], entries: [classes[actionIndex]],
            append: false, maximumDistributions: limits.storedMaximumDistributions, store: &store)
        return try finish(classes: classes, actions: actions, featureChannelMetadata: featureChannelMetadata,
            maximumClasses: limits.maximumClasses,
            maximumCanonicalDiagonalAdditions: limits.maximumCanonicalDiagonalAdditions, cache: &cache)
    }

    private static func finish(classes: [ReferenceTrainingBank.ClassEntry], actions: [Int32],
                               featureChannelMetadata: [[Double]], maximumClasses: Int,
                               maximumCanonicalDiagonalAdditions: Int,
                               cache: inout ReferenceClassifierCache<Signature>) throws -> Result {
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
