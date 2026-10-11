import Foundation

/// Comparison-only bridge from converted profile settings and an explicit input
/// montage to the shared raw workflow. No hardware IDs, quality, profile selection
/// or learned model are inferred. Does not replace qualified acquisition.
struct ReferenceResolvedMentalWorkflow {
    enum Failure: Error { case invalidMontage, invalidBlock }
    struct Settings {
        let sampleRate: Int
        let maximumBufferedSamples: Int
        let maximumSamplesPerBlock: Int
        let maximumFeatures: Int
        let backgroundEnabled: Bool
        let actions: [Int]
        let activationSetting: Int
    }
    struct Frame {
        /// Original full-montage measurement rows, including unselected channels.
        let inputSamples: [[Double]]
        let raw: ReferenceRawMentalWorkflow.Frame
    }
    let inputChannels: [UInt32]
    let resolved: ReferenceRuntimeRecipe.Resolved
    /// The same recipe can be supplied to the existing training/persistence path.
    let rawRecipe: ReferenceRawMentalWorkflow.Recipe
    private var workflow: ReferenceRawMentalWorkflow
    var bufferedSamples: Int { workflow.bufferedSamples }

    init(profile: ReferenceRuntimeRecipe.ConvertedProfile, headsetTypeID: Int32,
         inputChannels: [UInt32], settings: Settings,
         runtime: ReferenceRuntimeProfile.Runtime?) throws {
        // Independent resource bound. Duplicate IDs retain resolver first-match
        // semantics; no sorting, deduplication or presumed physical row order.
        guard !inputChannels.isEmpty, inputChannels.count <= 70 else { throw Failure.invalidMontage }
        let resolved = try ReferenceRuntimeRecipe.resolve(profile, headsetTypeID: headsetTypeID,
            inputChannels: inputChannels, maximumFeatures: settings.maximumFeatures)
        let recipe = ReferenceRawMentalWorkflow.Recipe(sampleRate: settings.sampleRate,
            selectedChannelCount: resolved.targetChannels.count,
            windowSeconds: resolved.recipe.windowSeconds, stepSeconds: resolved.recipe.stepSeconds,
            maximumBufferedSamples: settings.maximumBufferedSamples,
            maximumSamplesPerBlock: settings.maximumSamplesPerBlock,
            bands: resolved.recipe.bands, features: resolved.features,
            backgroundEnabled: settings.backgroundEnabled, actions: settings.actions,
            activationSetting: settings.activationSetting)
        workflow = try .init(recipe: recipe, runtime: runtime)
        self.inputChannels = inputChannels; self.resolved = resolved; rawRecipe = recipe
    }

    /// One caller-scheduled detector invocation, including explicit empty backlog
    /// ticks. Quality is the caller's reference-scale manager input, not raw CQ.
    /// Whole-matrix finite/shape rejection is our policy, including unused rows.
    mutating func process(inputSamples: [[Double]], overallContactQuality: Double,
                          managerControl: ReferenceManagerCadence.Control? = nil) throws -> Frame {
        if !inputSamples.isEmpty {
            guard inputSamples.count == inputChannels.count,
                  let width = inputSamples.first?.count,
                  width <= rawRecipe.maximumSamplesPerBlock,
                  inputSamples.allSatisfy({ $0.count == width && $0.allSatisfy(\.isFinite) }) else {
                throw Failure.invalidBlock
            }
        }
        let selected = inputSamples.isEmpty ? [] : resolved.inputIndices.map { inputSamples[$0] }
        let raw = try workflow.process(selectedChannelSamples: selected,
            overallContactQuality: overallContactQuality, managerControl: managerControl)
        return .init(inputSamples: inputSamples, raw: raw)
    }

    /// Shared independent discontinuity policy; not vendor manager.stop semantics.
    mutating func resetForGap() { workflow.resetForGap() }
}
