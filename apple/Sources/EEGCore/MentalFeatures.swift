import Foundation

/// Native implementation of the independent eeg.features.v1 design.
/// This numerical vector does not establish epoch readiness or command validity.
public struct EEGMentalFeatures: Sendable {
    public let values: [Double]
    public let artifactFlags: [String]
    public let channels: [EEGSpectrumResult]
    public var usable: Bool { artifactFlags.isEmpty }
    public static let configurationID = "affb28d9e76b8e68e3a55fcec4e4da0c8ee57e5118073876f505d35ee0c934fc"
    public static let channelOrder = ["AF3", "F7", "F3", "FC5", "T7", "P7", "O1", "O2", "P8", "T8", "FC6", "F4", "F8", "AF4"]
    public static let names = channelOrder.flatMap { channel in
        ["1-4", "4-8", "8-13", "13-30", "30-40"].map { "\(channel).logpower.\($0)Hz" }
    }
    public static func extract(samples: [EEGSample]) throws -> EEGMentalFeatures {
        let spectra = try channelOrder.map { try EEGSpectrum.analyze(samples: samples, channel: $0) }
        // Stable order matches the Python reference regardless of affected channel.
        let flags = ["high_amplitude_artifact_possible", "high_rms_artifact_possible", "flat_channel"].filter { flag in
            spectra.contains { $0.artifactFlags.contains(flag) }
        }
        return EEGMentalFeatures(values: spectra.flatMap { $0.bands.map(\.log10Power) }, artifactFlags: flags, channels: spectra)
    }
}
