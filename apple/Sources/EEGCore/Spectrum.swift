import Foundation

public struct EEGBandPower: Codable, Sendable, Equatable {
    public let name: String
    public let lowHz: Double
    public let highHz: Double
    public let powerMicrovoltsSquared: Double
    public let log10Power: Double
}

public struct EEGSpectrumResult: Codable, Sendable {
    public let channel: String
    public let frequenciesHz: [Double]
    public let densityMicrovoltsSquaredPerHz: [Double]
    public let bands: [EEGBandPower]
    public let detrendedRMSMicrovolts: Double
    public let peakToPeakMicrovolts: Double
    public let artifactFlags: [String]
    public var usable: Bool { artifactFlags.isEmpty }
    public var interpretation: String { "Descriptive signal analysis; artifact thresholds are unvalidated." }
}

public enum EEGSpectrumError: Error, LocalizedError, Equatable {
    case unsupportedWindow, unsupportedChannel, invalidTiming, discontinuity, missingCalibration, invalidVoltage
    public var errorDescription: String? {
        switch self {
        case .unsupportedWindow: return "Spectrum requires exactly 256 samples at the observed 128 Hz configuration."
        case .unsupportedChannel: return "Select a supported electrode."
        case .invalidTiming: return "Sample arrival timing is incompatible with this analysis."
        case .discontinuity: return "The analysis window contains missing or discontinuous samples."
        case .missingCalibration: return "Calibrated voltage data is unavailable for the selected electrode."
        case .invalidVoltage: return "Voltage is invalid, rail-clipped or inconsistent with ADC conversion."
        }
    }
}

/// One-window Welch PSD matching processing/features.py: linear detrend, periodic
/// Hann, density normalization, one-sided bins and half-open integrated bands.
/// Callers must separately enforce epoch/transport readiness: EEGSample alone does
/// not encode those fields. No inferred contact, emotion or mental-state score.
public enum EEGSpectrum {
    public static let featureVersion = "eeg.features.v1"
    public static let sampleCount = 256
    public static let observedSampleRate: Double = 128
    private static let count = 256
    private static let hann = (0..<count).map { 0.5 - 0.5 * cos(2 * .pi * Double($0) / Double(count)) }
    private static let normalization = 128.0 * hann.reduce(0) { $0 + $1 * $1 }
    // Cached deterministic DFT bases avoid repeatedly evaluating trigonometry.
    private static let cosine = (0...count / 2).map { k in
        (0..<count).map { n in cos(2 * .pi * Double(k * n) / Double(count)) }
    }
    private static let sine = (0...count / 2).map { k in
        (0..<count).map { n in sin(2 * .pi * Double(k * n) / Double(count)) }
    }

    public static func analyze(samples: [EEGSample], channel: String, sampleRate: Double = 128) throws -> EEGSpectrumResult {
        guard samples.count == count, sampleRate == observedSampleRate else { throw EEGSpectrumError.unsupportedWindow }
        guard EPOCProtocol.electrodeWords.contains(where: { $0.name == channel }) else { throw EEGSpectrumError.unsupportedChannel }
        guard samples.allSatisfy({ $0.receivedAt.isFinite && $0.receivedAt >= 0 }) else { throw EEGSpectrumError.invalidTiming }
        guard samples.allSatisfy({ $0.continuous && $0.index >= 0 && (0..<128).contains($0.counter) }) else { throw EEGSpectrumError.discontinuity }
        for (a, b) in zip(samples, samples.dropFirst()) {
            guard b.index == a.index + 1, b.counter == (a.counter + 1) % 128 else { throw EEGSpectrumError.discontinuity }
            guard b.receivedAt >= a.receivedAt, b.receivedAt - a.receivedAt <= 0.5 else { throw EEGSpectrumError.invalidTiming }
        }
        let span = samples[count - 1].receivedAt - samples[0].receivedAt
        guard span > 0, (120...136).contains(Double(count - 2) / span) else { throw EEGSpectrumError.invalidTiming }
        var values = [Double](); values.reserveCapacity(count)
        for sample in samples {
            guard let value = sample.electrodesMicrovolts?[channel], let adc = sample.electrodesADC[channel] else { throw EEGSpectrumError.missingCalibration }
            guard value.isFinite, adc.isFinite, value > 0, value < 65535.0 / 7.8,
                  abs(value - adc / 7.8) <= 1e-6 else { throw EEGSpectrumError.invalidVoltage }
            values.append(value)
        }
        let mean = values.reduce(0, +) / Double(count)
        let midpoint = Double(count - 1) / 2
        var numerator = 0.0; var denominator = 0.0
        for i in 0..<count {
            let t = Double(i) - midpoint
            numerator += t * (values[i] - mean); denominator += t * t
        }
        let slope = numerator / denominator
        let centered = (0..<count).map { values[$0] - mean - slope * (Double($0) - midpoint) }
        let rms = sqrt(centered.reduce(0) { $0 + $1 * $1 } / Double(count))
        let peakToPeak = centered.max()! - centered.min()!
        let tapered = zip(centered, hann).map(*)
        var power = [Double](); power.reserveCapacity(count / 2 + 1)
        for k in 0...count / 2 {
            var real = 0.0; var imaginary = 0.0
            for n in 0..<count { real += tapered[n] * cosine[k][n]; imaginary -= tapered[n] * sine[k][n] }
            let oneSided = (k == 0 || k == count / 2) ? 1.0 : 2.0
            power.append((real * real + imaginary * imaginary) * oneSided / normalization)
        }
        let frequencies = (0...count / 2).map { Double($0) * sampleRate / Double(count) }
        let definitions: [(String, Double, Double)] = [("Delta", 1, 4), ("Theta", 4, 8), ("Alpha", 8, 13), ("Beta", 13, 30), ("Gamma", 30, 40)]
        let bands = definitions.map { name, low, high -> EEGBandPower in
            let integrated = zip(frequencies, power).reduce(0.0) { result, bin in
                result + (bin.0 >= low && bin.0 < high ? bin.1 * sampleRate / Double(count) : 0)
            }
            return EEGBandPower(name: name, lowHz: low, highHz: high, powerMicrovoltsSquared: integrated, log10Power: log10(max(integrated, 1e-12)))
        }
        var flags = [String]()
        if peakToPeak > 500 { flags.append("high_amplitude_artifact_possible") }
        if rms > 100 { flags.append("high_rms_artifact_possible") }
        if rms < 1e-8 { flags.append("flat_channel") }
        return EEGSpectrumResult(channel: channel, frequenciesHz: frequencies, densityMicrovoltsSquaredPerHz: power,
                                 bands: bands, detrendedRMSMicrovolts: rms, peakToPeakMicrovolts: peakToPeak, artifactFlags: flags)
    }
}
