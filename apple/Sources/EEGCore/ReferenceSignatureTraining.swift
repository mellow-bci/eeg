import Foundation

/// Comparison-only orchestration derived from GaussianTraining::run,
/// combineClassGaussian and buildSignatureFromPCA. Fitting inputs still require
/// explicitly derived PCA/canonical artifacts; no profile recipe is fabricated.
enum ReferenceSignatureTraining {
    typealias Distribution = ReferenceGaussianPooling.Distribution
    enum InputError: Error, Equatable {
        case insufficientClasses, invalidClassReference, emptyClass, invalidShape, invalidMetadata, invalidFit
    }
    struct ClassAlgebra {
        let classReferenceID: Int32
        let distributions: [Distribution]
    }
    struct CombinedClass {
        let classReferenceID: Int32
        let distribution: Distribution?
    }
    struct Preparation {
        /// Original IDs retained as our provenance; pooled vendor slots have ID−1.
        let sourceClassReferenceIDs: [Int32]
        let pooledClasses: [CombinedClass]
        let selectedClasses: [Distribution]
        let selectedCoordinates: [Int]
        let channelsInUse: [UInt64]
    }
    struct FittedClass {
        let mean: [Double]
        let covariance: [[Double]]
    }
    struct Signature {
        let preparation: Preparation
        let pca: ReferenceGaussianPipeline.CenteredTransform
        let canonical: ReferenceGaussianPipeline.CenteredTransform
        let classes: [ReferenceGaussianPipeline.Mixture]
    }
    struct FittedArtifacts {
        let pca: ReferenceGaussianPipeline.CenteredTransform
        let canonical: ReferenceGaussianPipeline.CenteredTransform
        let classes: [FittedClass]
    }

    /// One orchestration path with an explicit, independently implemented fitting
    /// stage. This callback is required: it is not a fake/default fitted profile.
    /// Validation errors propagate; no partial signature is returned as success.
    static func run(_ classes: [ClassAlgebra], featureChannelMetadata: [[Double]],
                    fit: (Preparation) throws -> FittedArtifacts) throws -> Signature {
        let preparation = try prepare(classes, featureChannelMetadata: featureChannelMetadata)
        let fitted = try fit(preparation)
        return try assemble(preparation, pca: fitted.pca, canonical: fitted.canonical, fittedClasses: fitted.classes)
    }

    /// Source order matters: update times use the existing pairwise pooling rule.
    /// The first combine with an empty GaussianData copies the first distribution.
    static func combineClass(_ source: ClassAlgebra, preserveClassReference: Bool) throws -> CombinedClass {
        var accumulated: Distribution?
        for distribution in source.distributions {
            accumulated = try ReferenceGaussianPooling.combine(accumulated, distribution,
                                                                 useFirstUpdateTime: preserveClassReference)
        }
        return CombinedClass(classReferenceID: preserveClassReference ? source.classReferenceID : -1,
                             distribution: accumulated)
    }

    /// run's supported prefix: class folding -> coordinate selection -> slicing.
    /// Empty classes and malformed metadata fail explicitly under our bounded
    /// policy; the vendor's failed-build/partially-mutated classifier is not exposed.
    static func prepare(_ classes: [ClassAlgebra], featureChannelMetadata: [[Double]]) throws -> Preparation {
        guard classes.count >= 2 else { throw InputError.insufficientClasses }
        guard classes.allSatisfy({ $0.classReferenceID != -1 }) else { throw InputError.invalidClassReference }
        guard !featureChannelMetadata.isEmpty,
              let columns = featureChannelMetadata.first?.count, columns > 0,
              featureChannelMetadata.allSatisfy({ $0.count == columns }) else { throw InputError.invalidShape }
        let combined = try classes.map { try combineClass($0, preserveClassReference: false) }
        let distributions = try combined.map { value -> Distribution in
            guard let distribution = value.distribution else { throw InputError.emptyClass }
            guard distribution.mean.count == featureChannelMetadata.count else { throw InputError.invalidShape }
            return distribution
        }
        let selection = try ReferenceFeatureSelection.select(distributions.map { d in
            .init(mean: d.mean, variance: d.mean.indices.map { d.covariance[$0][$0] }, epochCounts: d.counts)
        })
        let coordinates = selection.selectedCoordinates
        let selected = distributions.map { d in
            Distribution(counts: coordinates.map { d.counts[$0] }, mean: coordinates.map { d.mean[$0] },
                         covariance: coordinates.map { r in coordinates.map { d.covariance[r][$0] } },
                         updateTime: d.updateTime)
        }
        return Preparation(sourceClassReferenceIDs: classes.map(\.classReferenceID), pooledClasses: combined,
                           selectedClasses: selected, selectedCoordinates: coordinates,
                           channelsInUse: try extractChannels(coordinates: coordinates, metadata: featureChannelMetadata))
    }

    /// extractChannelInUse scans columns 0,2,...,<2*floor(cols/2), casts to
    /// unsigned integer and inserts into a sorted set. Odd trailing columns are
    /// not read. No interpretation of adjacent metadata columns is invented.
    static func extractChannels(coordinates: [Int], metadata: [[Double]]) throws -> [UInt64] {
        guard let width = metadata.first?.count, metadata.allSatisfy({ $0.count == width }),
              coordinates.allSatisfy({ $0 >= 0 && $0 < metadata.count }) else { throw InputError.invalidShape }
        var channels = Set<UInt64>()
        for coordinate in coordinates {
            for column in stride(from: 0, to: (width / 2) * 2, by: 2) {
                let value = metadata[coordinate][column]
                // Our bounded conversion policy excludes vendor saturation and
                // values beyond exact binary64 integer representation.
                guard value.isFinite, value >= 0, value <= 9_007_199_254_740_991 else {
                    throw InputError.invalidMetadata
                }
                channels.insert(UInt64(value.rounded(.towardZero)))
            }
        }
        return channels.sorted()
    }

    /// Supported signature assembly after actual fitting. Caller supplies the
    /// fitted centers/bases and final canonical Gaussian means/covariances.
    /// One component of weight 1 is evidenced by buildSignature's 1x1 ones
    /// helper. Class priors/neutral scale and training acceptance are separate.
    static func assemble(_ preparation: Preparation,
                         pca: ReferenceGaussianPipeline.CenteredTransform,
                         canonical: ReferenceGaussianPipeline.CenteredTransform,
                         fittedClasses: [FittedClass]) throws -> Signature {
        let classCount = preparation.selectedClasses.count
        let selectedWidth = preparation.selectedCoordinates.count
        guard classCount >= 2, fittedClasses.count == classCount,
              pca.mean.count == selectedWidth, pca.basis.count == selectedWidth,
              let pcaWidth = pca.basis.first?.count, pcaWidth >= classCount - 1,
              pca.basis.allSatisfy({ $0.count == pcaWidth }),
              canonical.mean.count == pcaWidth, canonical.basis.count == pcaWidth,
              let canonicalWidth = canonical.basis.first?.count, canonicalWidth >= classCount - 1,
              canonical.basis.allSatisfy({ $0.count == canonicalWidth }) else { throw InputError.invalidFit }
        let dimension = classCount - 1
        guard [pca.mean, canonical.mean].allSatisfy({ $0.allSatisfy(\.isFinite) }),
              [pca.basis, canonical.basis].allSatisfy({ $0.allSatisfy({ $0.allSatisfy(\.isFinite) }) }),
              fittedClasses.allSatisfy({ c in
                  c.mean.count == dimension && c.mean.allSatisfy(\.isFinite) && c.covariance.count == dimension &&
                      c.covariance.allSatisfy({ $0.count == dimension && $0.allSatisfy(\.isFinite) })
              }) else { throw InputError.invalidFit }
        // Validate covariance via the existing strict-SPD Gaussian density kernel.
        let mixtures = try fittedClasses.map { c in
            let component = ReferenceGaussianPipeline.Component(weight: 1, mean: c.mean, covariance: c.covariance)
            _ = try ReferenceGaussianPipeline.gaussianDensity(c.mean, component: component)
            return ReferenceGaussianPipeline.Mixture(components: [component])
        }
        return Signature(preparation: preparation, pca: pca, canonical: canonical, classes: mixtures)
    }
}
