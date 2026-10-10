import Foundation

/// Comparison-only typed profile bridge. JSON schema acceptance is distinct from
/// an executable classifier. No profile-derived priors, thresholds or defaults.
/// Body evidence: runtime-field-continuation-20261011.
enum ReferenceRuntimeProfile {
    typealias Codec = ReferenceProfileCodec
    typealias Kernel = ReferenceGaussianPipeline
    enum InputError: Error, Equatable {
        case invalidShape, invalidFeatureIndex, unsupportedClassCount, invalidMetadata
    }
    struct Runtime {
        let featureIndices: [Int]
        let parameters: Kernel.Parameters
        /// Metadata retained for callers; neither is a scoring coefficient.
        let classReferenceIDs: [Int32]
        let channelInUse: Codec.Matrix
        let useCount: UInt64
    }

    /// WMV mean columns are mixture components; covariance vector shares that
    /// order. Only the finite, positive-shape, <=70-dimensional domain is supported.
    static func runtime(_ profile: Codec.Classifier, classPriors: [Double],
                        neutralScale: Double) throws -> Runtime {
        let count = profile.weightMeanVariances.count
        guard count >= 2 else { throw InputError.unsupportedClassCount }
        guard profile.classRefIDs.count == count, classPriors.count == count,
              !profile.uniqueFeatureIndices.isEmpty,
              profile.uniqueFeatureIndices.allSatisfy({ $0 <= UInt64(Int.max) }) else {
            throw InputError.invalidShape
        }
        let indices = profile.uniqueFeatureIndices.map(Int.init)
        let pcaBasis = try profile.coeff.rowValues()
        let pcaMean = try row(profile.pcMeans)
        guard pcaBasis.count == indices.count, pcaMean.count == indices.count,
              profile.numOfValidFeatures > 0,
              profile.numOfValidFeatures <= UInt64(profile.coeff.columns),
              profile.numOfValidFeatures <= 70 else { throw InputError.invalidShape }
        let retained = Int(profile.numOfValidFeatures)
        let canonicalBasis = try profile.eigenvec.rowValues()
        let canonicalMean = try row(profile.meanTot)
        guard canonicalBasis.count == retained, canonicalMean.count == retained,
              profile.eigenvec.columns >= count - 1, count - 1 <= 70 else { throw InputError.invalidShape }
        let mixtures = try profile.weightMeanVariances.map { entry -> Kernel.Mixture in
            let weights = try entry.weight.rowValues()
            let means = try entry.mean.rowValues()
            let components = entry.weight.rows
            guard components > 0, entry.weight.columns == 1,
                  entry.mean.rows == count - 1, entry.mean.columns == components,
                  entry.variances.count == components else { throw InputError.invalidShape }
            return Kernel.Mixture(components: try (0..<components).map { component in
                let covariance = try entry.variances[component].rowValues()
                guard covariance.count == count - 1,
                      covariance.allSatisfy({ $0.count == count - 1 }) else { throw InputError.invalidShape }
                let value = Kernel.Component(weight: weights[component][0],
                    mean: means.map { $0[component] }, covariance: covariance)
                _ = try Kernel.gaussianDensity(value.mean, component: value)
                return value
            })
        }
        // Algebraically equivalent to full PCA followed by leading-column slice.
        // We retain only those columns in the existing kernel; no new math path.
        let parameters = Kernel.Parameters(
            pca: .init(mean: pcaMean, basis: pcaBasis.map { Array($0.prefix(retained)) }),
            canonical: .init(mean: canonicalMean, basis: canonicalBasis),
            canonicalClassCount: count, classes: mixtures,
            classPriors: classPriors, neutralScale: neutralScale)
        // Validate explicit posterior settings using the existing normalization contract.
        _ = try Kernel.posterior(density: Array(repeating: 1, count: count),
            peakDensity: Array(repeating: 1, count: count), priors: classPriors, neutralScale: neutralScale)
        return Runtime(featureIndices: indices, parameters: parameters,
            classReferenceIDs: profile.classRefIDs, channelInUse: profile.channelInUse, useCount: profile.useCount)
    }

    static func infer(featureVector: [Double], runtime: Runtime) throws -> Kernel.Result {
        guard runtime.featureIndices.allSatisfy({ $0 >= 0 && $0 < featureVector.count }) else {
            throw InputError.invalidFeatureIndex
        }
        // Preserve selector order and repetitions; do not sort or deduplicate.
        return try Kernel.infer(featureVector: runtime.featureIndices.map { featureVector[$0] },
                                parameters: runtime.parameters)
    }

    /// Pack our independently fitted signature into the observed logical layout.
    /// Retained PCA width and lifecycle counter are explicit caller inputs rather
    /// than an invented build/acceptance policy. This does not claim Qt byte parity.
    static func classifier(_ signature: ReferenceSignatureTraining.Signature,
                           numOfValidFeatures: Int, useCount: UInt64) throws -> Codec.Classifier {
        guard numOfValidFeatures > 0, useCount <= UInt64(Int32.max),
              signature.preparation.selectedCoordinates.allSatisfy({ $0 >= 0 }),
              signature.preparation.channelsInUse.allSatisfy({ $0 <= 9_007_199_254_740_991 }) else {
            throw InputError.invalidMetadata
        }
        let entries = try signature.classes.map { mixture -> Codec.WeightMeanVariances in
            let components = mixture.components
            guard let width = components.first?.mean.count, width > 0,
                  components.allSatisfy({ $0.mean.count == width }) else { throw InputError.invalidShape }
            return .init(weight: try Codec.Matrix.fromRows(components.map { [$0.weight] }),
                mean: try Codec.Matrix.fromRows((0..<width).map { row in components.map { $0.mean[row] } }),
                variances: try components.map { try Codec.Matrix.fromRows($0.covariance) })
        }
        return Codec.Classifier(weightMeanVariances: entries,
            classRefIDs: signature.preparation.sourceClassReferenceIDs,
            uniqueFeatureIndices: signature.preparation.selectedCoordinates.map(UInt64.init),
            coeff: try Codec.Matrix.fromRows(signature.pca.basis),
            pcMeans: try Codec.Matrix.fromRows([signature.pca.mean]),
            eigenvec: try Codec.Matrix.fromRows(signature.canonical.basis),
            meanTot: try Codec.Matrix.fromRows([signature.canonical.mean]),
            channelInUse: try Codec.Matrix.fromRows([signature.preparation.channelsInUse.map { Double($0) }]),
            numOfValidFeatures: UInt64(numOfValidFeatures), useCount: useCount)
    }

    private static func row(_ matrix: Codec.Matrix) throws -> [Double] {
        guard matrix.rows == 1, matrix.columns > 0 else { throw InputError.invalidShape }
        return try matrix.rowValues()[0]
    }
}
