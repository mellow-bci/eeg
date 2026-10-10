import Foundation

/// Comparison-only raw selected-channel composition. Inputs are decoded measurements
/// in an EXPLICIT caller-selected row order, not BLE packets or an inferred montage.
/// Body order: manager input filter -> MatrixStream -> median preprocessing ->
/// Hamming -> FFT -> bands -> power/ratio -> clean/background -> runtime -> scoring.
/// Actual deployed bands, coordinates, step, quality and profile remain supplied.
struct ReferenceRawMentalWorkflow {
    enum Failure: Error { case invalidRecipe, invalidBlock, incompatibleRuntime }
    enum Status: Equatable { case waiting, consumedWithoutFeatures, qualityRejected, featuresOnly, inferred }
    struct Recipe {
        let sampleRate: Int
        let selectedChannelCount: Int
        let windowSeconds: Double
        let stepSeconds: Double
        let maximumBufferedSamples: Int
        let maximumSamplesPerBlock: Int
        let bands: [ReferenceSpectralPipeline.Band]
        let features: [ReferenceDeployedFeatures.Feature]
        let backgroundEnabled: Bool
        let actions: [Int]
        let activationSetting: Int
    }
    struct Frame {
        let status: Status
        let segment: UInt64
        /// Original input from this invocation, preserved separately from filtering.
        let selectedChannelSamples: [[Double]]
        let filteredBlock: [[Double]]
        let filteredEpoch: [[Double]]?
        let preprocessedEpoch: [[Double]]?
        let spectra: [[Double]]?
        let bandPowers: [[Double]]?
        let features: ReferenceProcessedEpoch.Features?
        let classification: ReferenceGaussianPipeline.Result?
        let filteredPosterior: [Double]?
        /// Diagnostic candidate only. Never dispatched to an application or OS.
        let command: ReferenceCommandScoring.Output?
    }

    let recipe: Recipe
    let runtime: ReferenceRuntimeProfile.Runtime?
    private var cadence: ReferenceManagerCadence
    private var processed = ReferenceProcessedEpoch()
    private var posteriorFilters: [ReferenceScoringLowpass]
    private var scorer: ReferenceCommandScoring
    private(set) var segment: UInt64 = 0
    var bufferedSamples: Int { cadence.bufferedSamples }

    init(recipe: Recipe, runtime: ReferenceRuntimeProfile.Runtime?) throws {
        guard recipe.selectedChannelCount > 0, recipe.selectedChannelCount <= 70,
              !recipe.bands.isEmpty, !recipe.features.isEmpty else { throw Failure.invalidRecipe }
        let stream = try ReferenceEpochStream(sampleRate: recipe.sampleRate,
            windowSeconds: recipe.windowSeconds, stepSeconds: recipe.stepSeconds,
            maximumBufferedSamples: recipe.maximumBufferedSamples)
        guard stream.windowSamples >= 2,
              stream.windowSamples & (stream.windowSamples - 1) == 0 else { throw Failure.invalidRecipe }
        func valid(_ coordinate: ReferenceDeployedFeatures.Coordinate) -> Bool {
            (0..<recipe.selectedChannelCount).contains(coordinate.row) && recipe.bands.indices.contains(coordinate.band)
        }
        for feature in recipe.features {
            switch feature {
            case .power(let coordinate): guard valid(coordinate) else { throw Failure.invalidRecipe }
            case .ratio(let numerator, let denominator):
                guard valid(numerator), valid(denominator) else { throw Failure.invalidRecipe }
            }
        }
        guard recipe.bands.allSatisfy({ $0.lowerHz.isFinite && $0.upperHz.isFinite &&
            $0.lowerHz >= 0 && $0.upperHz >= $0.lowerHz }) else { throw Failure.invalidRecipe }
        if let runtime {
            guard runtime.classReferenceIDs == ([Int32(1)] + recipe.actions.compactMap { Int32(exactly: $0) }),
                  runtime.parameters.classes.count == recipe.actions.count + 1,
                  runtime.featureIndices.allSatisfy({ recipe.features.indices.contains($0) }) else {
                throw Failure.incompatibleRuntime
            }
        }
        self.recipe = recipe; self.runtime = runtime
        cadence = try ReferenceManagerCadence(configuration: Self.cadenceConfiguration(recipe))
        scorer = try ReferenceCommandScoring(actions: recipe.actions, activationSetting: recipe.activationSetting)
        posteriorFilters = Array(repeating: .init(), count: recipe.actions.count + 2)
    }

    /// Our explicit discontinuity policy: discard partial windows, filter history,
    /// background and scoring history together. This is not a recovered automatic
    /// vendor gap detector. Caller must mark transport gaps or changed calibration.
    mutating func resetForGap() {
        cadence.resetForGap()
        processed = ReferenceProcessedEpoch()
        resetScoring(); segment &+= 1
    }

    private static func cadenceConfiguration(_ recipe: Recipe) -> ReferenceManagerCadence.Configuration {
        .init(sampleRate: recipe.sampleRate, windowSeconds: recipe.windowSeconds, stepSeconds: recipe.stepSeconds,
              selectedChannelCount: recipe.selectedChannelCount, maximumBufferedSamples: recipe.maximumBufferedSamples,
              maximumSamplesPerBlock: recipe.maximumSamplesPerBlock)
    }

    private mutating func resetScoring() {
        posteriorFilters = Array(repeating: .init(), count: recipe.actions.count + 2)
        scorer.reset()
    }

    /// Exactly one manager-like invocation and at most one epoch. An empty outer
    /// array means no new input, allowing an explicitly scheduled backlog tick.
    /// Quality applies to the emitted epoch, not every sample in the new block.
    /// It must be provided on the reference numeric scale; no quality decoding is
    /// fabricated. Numeric/input failures reject the invocation atomically (ours).
    mutating func process(selectedChannelSamples: [[Double]], overallContactQuality: Double,
                          managerControl: ReferenceManagerCadence.Control? = nil) throws -> Frame {
        guard overallContactQuality.isFinite else { throw Failure.invalidBlock }
        var next = self
        let result = try next.processUnchecked(selectedChannelSamples, quality: overallContactQuality, control: managerControl)
        self = next
        return result
    }

    /// nil control selects the existing diagnostic feature path. Explicit controls
    /// opt into the recovered manager feature-consumption gate. No model is invented.
    private mutating func processUnchecked(_ input: [[Double]], quality: Double,
                                          control: ReferenceManagerCadence.Control?) throws -> Frame {
        let tick = try cadence.detectorCall(selectedChannels: input, control: control ??
            .init(classifierEmpty: runtime == nil, autoSamplingNeutral: false, trainingControl: 1))
        let filtered = tick.filteredBlock
        guard let epoch = tick.featureInput else {
            return Frame(status: tick.route == .consumedWithoutFeatures ? .consumedWithoutFeatures : .waiting,
                segment: segment, selectedChannelSamples: input,
                filteredBlock: filtered, filteredEpoch: tick.consumedEpoch, preprocessedEpoch: nil, spectra: nil,
                bandPowers: nil, features: nil, classification: nil, filteredPosterior: nil, command: nil)
        }
        let preprocessed = try ReferenceSpectralPipeline.preprocess(epoch)
        let spectra = try preprocessed.map { try ReferenceSpectralPipeline.spectrum(ReferenceMentalKernels.window($0)) }
        let bands = try spectra.map { try ReferenceSpectralPipeline.bands($0,
            sampleRate: Double(recipe.sampleRate), bands: recipe.bands) }
        let original = try ReferenceDeployedFeatures.extract(channelBands: bands, features: recipe.features)
        let features = try processed.process(original,
            clean: ReferenceDeployedFeatures.overallContactIsClean(quality), backgroundEnabled: recipe.backgroundEnabled)
        let classification: ReferenceGaussianPipeline.Result?
        let posterior: [Double]?
        let command: ReferenceCommandScoring.Output?
        let status: Status
        if !features.clean {
            // Our fail-closed qualification policy, not an asserted vendor reset:
            // no stale candidate may be emitted after an invalid-quality epoch.
            resetScoring(); status = .qualityRejected
            classification = nil; posterior = nil; command = nil
        } else if let runtime {
            let result = try ReferenceRuntimeProfile.infer(featureVector: features.processed, runtime: runtime)
            let smoothed = try result.posterior.indices.map {
                try posteriorFilters[$0].process([result.posterior[$0]])[0]
            }
            classification = result; posterior = smoothed
            command = try scorer.process(filteredProbabilities: smoothed); status = .inferred
        } else {
            classification = nil; posterior = nil; command = nil; status = .featuresOnly
        }
        return Frame(status: status, segment: segment, selectedChannelSamples: input,
            filteredBlock: filtered, filteredEpoch: epoch, preprocessedEpoch: preprocessed,
            spectra: spectra, bandPowers: bands, features: features, classification: classification,
            filteredPosterior: posterior, command: command)
    }
}
