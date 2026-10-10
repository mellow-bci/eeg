/// Body-supported default-profile recipe and coordinate construction. This is an
/// opt-in comparison preset, not proof of the currently loaded headset profile.
/// Runtime profile values override these defaults; no live acquisition is changed.
enum ReferenceDeployedRecipe {
    enum Failure: Error, Equatable { case resourceLimit, invalidConfiguration, missingChannel(UInt32) }
    struct Defaults: Sendable {
        var windowSeconds: Double = 1
        var stepSeconds: Double = 0.125
        var isBandPower: Bool = true
        var bands: [ReferenceSpectralPipeline.Band] = [
            .init(lowerHz: 4,upperHz: 7),.init(lowerHz: 8,upperHz: 12),
            .init(lowerHz: 13,upperHz: 17),.init(lowerHz: 18,upperHz: 22),
            .init(lowerHz: 23,upperHz: 26),.init(lowerHz: 27,upperHz: 30),
            .init(lowerHz: 31,upperHz: 57)
        ]
    }
    static let defaultProfile = Defaults()

    /// Traced installed-build HeadsetType numeric dispatch only. This does not
    /// qualify any headset, infer its enum ID, or replace profile eegChannels.
    static func targetChannels(forHeadsetTypeID id: Int32) -> [UInt32] {
        switch id {
        case 1,2: return [40,54,72,92,106]
        case 9,10: return [54,92]
        default: return [40,43,45,51,54,64,69,77,82,92,95,101,103,106]
        }
    }

    /// First matching position preserves target order. Missing targets fail;
    /// caller supplies actual input IDs, not an assumed device row order.
    static func inputIndices(targetChannels: [UInt32], inputChannels: [UInt32]) throws -> [Int] {
        try targetChannels.map { target in
            guard let index = inputChannels.firstIndex(of: target) else { throw Failure.missingChannel(target) }
            return index
        }
    }

    /// Exact normal-domain generateChannelBandMapping order. Caller cap is our
    /// resource policy; constructor overflow and negative dimensions unsupported.
    static func features(channelCount: Int, bandCount: Int, isBandPower: Bool,
                         maximumFeatures: Int) throws -> [ReferenceDeployedFeatures.Feature] {
        guard maximumFeatures >= 0 else { throw Failure.invalidConfiguration }
        guard channelCount > 0, bandCount > 0 else { return [] }
        guard channelCount <= 70, bandCount <= 70 else { throw Failure.resourceLimit }
        let count = isBandPower ? channelCount * bandCount :
            (channelCount * (channelCount + 1) / 2) * (bandCount * (bandCount + 1) / 2) - channelCount * bandCount
        guard count <= maximumFeatures, count <= Int(Int32.max) else { throw Failure.resourceLimit }
        var result: [ReferenceDeployedFeatures.Feature] = []
        result.reserveCapacity(count)
        for channel in 0..<channelCount {
            for band in 0..<bandCount {
                let denominator = ReferenceDeployedFeatures.Coordinate(row: channel,band: band)
                if isBandPower { result.append(.power(denominator)); continue }
                for numeratorChannel in 0...channel {
                    for numeratorBand in 0...band {
                        if numeratorChannel == channel && numeratorBand == band { continue }
                        result.append(.ratio(numerator: .init(row: numeratorChannel,band: numeratorBand),
                                             denominator: denominator))
                    }
                }
            }
        }
        return result
    }
}
