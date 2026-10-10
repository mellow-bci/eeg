import Foundation

/// Comparison-only constructor recipe for the explicitly traced current configuration.
/// This is static binary evidence, not qualification of physical contact transitions.
enum ReferenceTypeSevenCQRecipe {
    enum Failure: Error { case unsupportedConfiguration }
    struct Channel {
        let calibrationChannelID: Int
        let rawEEGIndex: Int
        let configuration: ReferenceContactQualityMapping.ChannelConfiguration
    }
    struct Recipe {
        let mode: Int
        let eegSampleRate: Int
        let eegResolution: Int
        let motionSampleRate: Int
        let motionResolution: Int
        let channels: [Channel]
        // Distinct constructor fields. Initial state4 is not an observed good contact.
        let initialRememberedRawValues: [Double]
        let initialStates: [Int]

        func snapshot(rawValuesInCQOrdinalOrder: [Double]) throws -> ReferenceContactQualityMapping.Diagnostics {
            try ReferenceContactQualityMapping.snapshot(rawValues: rawValuesInCQOrdinalOrder,
                configurations: channels.map { $0.configuration },
                eeg16Bit: ReferenceContactQualityMapping.typeSevenUses16Bit(mode: mode),
                headsetType: 7, maximumChannels: 14)
        }
    }

    /// Gates are our bounded support policy. Byte-array branch and option copy are traced;
    /// no implicit device discovery, configuration writes, or remembered-slot updates occur.
    static func current(revision: UInt32, configurationBytes: [UInt8], connectionType: Int) throws -> Recipe {
        guard revision == 0x0740, configurationBytes == [0x01, 0x80, 0x00, 0x10, 0x20, 0x10],
              connectionType == 1 else { throw Failure.unsupportedConfiguration }
        let calibrationIDs = [45, 51, 40, 43, 54, 64, 69, 77, 82, 92, 103, 106, 95, 101]
        let indices = [0, 1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14]
        let divisors: [Int32] = [212, 216, 226, 235, 231, 239, 245, 179, 167, 162, 206, 204, 194, 179]
        let channels = calibrationIDs.indices.map { ordinal in
            Channel(calibrationChannelID: calibrationIDs[ordinal], rawEEGIndex: indices[ordinal],
                configuration: .init(offset: 0, divisor: divisors[ordinal],
                    thresholds: [0.2, 0.7, 1.3, 1.7], f68RangeGroup: false))
        }
        return Recipe(mode: 7, eegSampleRate: 128, eegResolution: 16,
            motionSampleRate: 32, motionResolution: 16, channels: channels,
            initialRememberedRawValues: Array(repeating: 0, count: 14),
            initialStates: Array(repeating: 4, count: 14))
    }
}
