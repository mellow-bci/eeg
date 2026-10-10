/// Comparison-only loaded-profile recipe. Values are already converted by the
/// caller: this does not emulate arbitrary QVariant coercions or edit capture.
enum ReferenceRuntimeRecipe {
    enum Value { case integer(Int32), floating(Double), matrix(ReferenceProfileCodec.Matrix) }
    struct ConvertedProfile {
        /// nil means invalid version QVariant; strings are already toString output.
        var version: String?
        var values: [String: Value]
    }
    enum Failure: Error, Equatable {
        case missingConvertedValue(String), unsupportedConvertedValue(String), unsupportedBands
    }
    struct Resolved {
        let usedDefaultProfile: Bool
        let recipe: ReferenceDeployedRecipe.Defaults
        let targetChannels: [UInt32]
        let inputIndices: [Int]
        let features: [ReferenceDeployedFeatures.Feature]

        /// Manager init creates a new stream and resets it; no state migration.
        func makeStream(sampleRate: Int, maximumBufferedSamples: Int) throws -> ReferenceEpochStream {
            try .init(sampleRate: sampleRate,windowSeconds: recipe.windowSeconds,
                      stepSeconds: recipe.stepSeconds,maximumBufferedSamples: maximumBufferedSamples)
        }
        /// Actual filter coefficients are fixed at init, independent of band/timing overrides.
        func makeFilter(maximumChannels: Int, maximumSamplesPerBlock: Int) throws -> ReferenceDeployedFilter {
            try .deployed(maximumChannels: maximumChannels,maximumSamplesPerBlock: maximumSamplesPerBlock)
        }
    }

    static func resolve(_ profile: ConvertedProfile, headsetTypeID: Int32,
                        inputChannels: [UInt32], maximumFeatures: Int) throws -> Resolved {
        let defaults = profile.version != "20180327"
        let recipe: ReferenceDeployedRecipe.Defaults
        if defaults {
            // The actual version branch calls whole default construction, not a
            // per-field merge with arbitrary old-version overrides.
            recipe = ReferenceDeployedRecipe.defaultProfile
        } else {
            let matrixKey = "cognitiv-bands"
            guard let raw = profile.values[matrixKey] else { throw Failure.missingConvertedValue(matrixKey) }
            guard case .matrix(let matrix) = raw else { throw Failure.unsupportedConvertedValue(matrixKey) }
            // Body iterates Matrix.cols linear values, ignoring further rows.
            let (size, overflow) = matrix.rows.multipliedReportingOverflow(by: matrix.columns)
            guard matrix.rows > 0, matrix.columns > 0, matrix.columns % 2 == 0,
                  !overflow, size == matrix.elements.count,
                  matrix.elements.prefix(matrix.columns).allSatisfy(\.isFinite) else {
                throw Failure.unsupportedBands
            }
            let edges = Array(matrix.elements.prefix(matrix.columns))
            let bands = stride(from: 0,to: edges.count,by: 2).map {
                ReferenceSpectralPipeline.Band(lowerHz: edges[$0],upperHz: edges[$0 + 1])
            }
            let mode = try integer("cognitiv-isBandPower",profile.values)
            let window = try floating("cognitiv-winSizeInSec",profile.values)
            let step = try floating("cognitiv-stepSizeInSec",profile.values)
            recipe = .init(windowSeconds: window,stepSeconds: step,isBandPower: mode == 1,bands: bands)
        }
        let targets = ReferenceDeployedRecipe.targetChannels(forHeadsetTypeID: headsetTypeID)
        let indices = try ReferenceDeployedRecipe.inputIndices(targetChannels: targets,inputChannels: inputChannels)
        let coordinates = try ReferenceDeployedRecipe.features(channelCount: targets.count,
            bandCount: recipe.bands.count,isBandPower: recipe.isBandPower,maximumFeatures: maximumFeatures)
        return .init(usedDefaultProfile: defaults,recipe: recipe,targetChannels: targets,
                     inputIndices: indices,features: coordinates)
    }

    private static func integer(_ key: String,_ values: [String: Value]) throws -> Int32 {
        guard let raw = values[key] else { throw Failure.missingConvertedValue(key) }
        guard case .integer(let value) = raw else { throw Failure.unsupportedConvertedValue(key) }
        return value
    }
    private static func floating(_ key: String,_ values: [String: Value]) throws -> Double {
        guard let raw = values[key] else { throw Failure.missingConvertedValue(key) }
        guard case .floating(let value) = raw, value.isFinite else { throw Failure.unsupportedConvertedValue(key) }
        return value
    }
}
