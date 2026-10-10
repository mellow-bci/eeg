import Foundation

/// Comparison-only composition of traced arithmetic. This is NOT the device
/// runtime recipe. Windows must already have the reference preprocessing and
/// channel selection applied. Every band and feature coordinate is explicit;
/// no vendor defaults, learned assets, sample cadence or device mapping is inferred.
struct ReferenceMentalPipeline {
    enum InputError: Error { case invalidRecipe, invalidWindow }
    struct Feature: Sendable, Codable {
        let series: Int
        let band: Int
    }
    struct Recipe: Sendable, Codable {
        let sampleRate: Double
        let samplesPerSeries: Int
        let seriesCount: Int
        let bands: [ReferenceSpectralPipeline.Band]
        /// Ordered coordinates after band power, including any repeated choices.
        /// A recovered feature recipe must be supplied; flattening is not guessed.
        let features: [Feature]
        let classifier: ReferenceGaussianPipeline.Parameters
        /// Classifier order must be [trained neutral, these actions...].
        let actions: [Int]
        let activationSetting: Int
    }
    struct Frame {
        let spectra: [[Double]]
        let bandPowers: [[Double]]
        let features: [Double]
        let classification: ReferenceGaussianPipeline.Result
        let filteredPosterior: [Double]
        let command: ReferenceCommandScoring.Output
    }

    let recipe: Recipe
    private var filters: [ReferenceScoringLowpass]
    private var scorer: ReferenceCommandScoring

    init(recipe: Recipe) throws {
        guard recipe.sampleRate.isFinite, recipe.sampleRate > 0,
              recipe.samplesPerSeries >= 2,
              recipe.samplesPerSeries & (recipe.samplesPerSeries - 1) == 0,
              recipe.seriesCount > 0, !recipe.bands.isEmpty, !recipe.features.isEmpty,
              recipe.features.allSatisfy({
                  (0..<recipe.seriesCount).contains($0.series) && recipe.bands.indices.contains($0.band)
              }), recipe.classifier.classes.count == recipe.actions.count + 1,
              recipe.classifier.canonicalClassCount == recipe.classifier.classes.count,
              recipe.classifier.pca.mean.count == recipe.features.count else {
            throw InputError.invalidRecipe
        }
        self.recipe = recipe
        filters = Array(repeating: ReferenceScoringLowpass(), count: recipe.actions.count + 2)
        scorer = try ReferenceCommandScoring(actions: recipe.actions,
                                           activationSetting: recipe.activationSetting)
    }

    mutating func reset() {
        for index in filters.indices { filters[index].reset() }
        scorer.reset()
    }

    /// One update per supplied window. Caller must reproduce reference cadence.
    /// State commits only after all stages succeed; failures do not consume history.
    /// A gap/profile change requires explicit reset by the comparison caller.
    mutating func process(preprocessedSeries: [[Double]]) throws -> Frame {
        guard preprocessedSeries.count == recipe.seriesCount,
              preprocessedSeries.allSatisfy({ $0.count == recipe.samplesPerSeries }) else {
            throw InputError.invalidWindow
        }
        let spectra = try preprocessedSeries.map {
            try ReferenceSpectralPipeline.spectrum(ReferenceMentalKernels.window($0))
        }
        let bands = try spectra.map {
            try ReferenceSpectralPipeline.bands($0, sampleRate: recipe.sampleRate, bands: recipe.bands)
        }
        let features: [Double]
        do {
            features = try ReferenceDeployedFeatures.extract(channelBands: bands,
                features: recipe.features.map { .power(.init(row: $0.series, band: $0.band)) })
        } catch { throw InputError.invalidWindow }
        let classification = try ReferenceGaussianPipeline.infer(featureVector: features,
                                                                 parameters: recipe.classifier)
        var nextFilters = filters
        var nextScorer = scorer
        let filtered = try classification.posterior.indices.map {
            try nextFilters[$0].process([classification.posterior[$0]])[0]
        }
        let command = try nextScorer.process(filteredProbabilities: filtered)
        filters = nextFilters
        scorer = nextScorer
        return Frame(spectra: spectra, bandPowers: bands, features: features,
                     classification: classification, filteredPosterior: filtered, command: command)
    }
}
