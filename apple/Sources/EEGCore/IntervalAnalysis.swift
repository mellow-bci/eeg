import Foundation

public struct EEGSpectrogramWindow: Codable, Sendable {
    /// Inclusive actual source indices. The center may fall between two samples.
    public let startIndex: Int
    public let endIndex: Int
    public let centerIndex: Double
    /// Host arrival timestamps, not reconstructed hardware sample timestamps.
    public let startTime: Double?
    public let endTime: Double?
    public let centerTime: Double?
    public let densityMicrovoltsSquaredPerHz: [Double]?
    public let artifactFlags: [String]
    public let rejectionReason: String?
    /// Numerical/structural acceptance only; artifact flags are not erased.
    public var accepted: Bool { densityMicrovoltsSquaredPerHz != nil && rejectionReason == nil }
}

public struct EEGIntervalAnalysisResult: Codable, Sendable {
    public let channel: String
    public let windowSize: Int
    public let hopSize: Int
    public let windows: [EEGSpectrogramWindow]
    public let frequenciesHz: [Double]
    public let meanDensityMicrovoltsSquaredPerHz: [Double]?
    public let trailingUncoveredSampleCount: Int
    public var acceptedWindowCount: Int { windows.filter(\.accepted).count }
    public var rejectedWindowCount: Int { windows.count - acceptedWindowCount }
    public var flaggedWindowCount: Int { windows.filter { !$0.artifactFlags.isEmpty }.count }
    public var averagingMethod: String { "Mean of structurally valid windows; 256 samples, 128-sample hop. Artifact flags retained." }
    public var interpretation: String { "Overlapping windows are for descriptive interval analysis, not independent training observations or physiological validation." }
}

/// Sliding descriptive PSD using the same verified spectral calculation as the
/// single-window display. No gap filling, interpolation, filtering or resampling.
public enum EEGIntervalAnalysis {
    public static let windowSize = 256
    public static let hopSize = 128

    public static func analyze(samples: [EEGSample], channel: String) throws -> EEGIntervalAnalysisResult {
        guard samples.count >= windowSize else { throw EEGSpectrumError.unsupportedWindow }
        guard EPOCProtocol.electrodeWords.contains(where: { $0.name == channel }) else { throw EEGSpectrumError.unsupportedChannel }
        var windows = [EEGSpectrogramWindow]()
        var sum = [Double](repeating: 0, count: windowSize / 2 + 1)
        var accepted = 0
        var lastCoveredOffset = 0
        for offset in stride(from: 0, through: samples.count - windowSize, by: hopSize) {
            let slice = Array(samples[offset..<offset + windowSize])
            let first = slice[0]; let last = slice[windowSize - 1]
            let leftCenter = slice[windowSize / 2 - 1]; let rightCenter = slice[windowSize / 2]
            var density: [Double]?; var flags = [String](); var reason: String?
            do {
                let result = try EEGSpectrum.analyze(samples: slice, channel: channel)
                density = result.densityMicrovoltsSquaredPerHz
                flags = result.artifactFlags
                for bin in sum.indices { sum[bin] += result.densityMicrovoltsSquaredPerHz[bin] }
                accepted += 1
            } catch { reason = error.localizedDescription }
            let centerTime = leftCenter.receivedAt / 2 + rightCenter.receivedAt / 2
            windows.append(EEGSpectrogramWindow(
                startIndex: first.index, endIndex: last.index,
                centerIndex: Double(leftCenter.index) / 2 + Double(rightCenter.index) / 2,
                startTime: first.receivedAt.isFinite ? first.receivedAt : nil,
                endTime: last.receivedAt.isFinite ? last.receivedAt : nil,
                centerTime: centerTime.isFinite ? centerTime : nil,
                densityMicrovoltsSquaredPerHz: density, artifactFlags: flags, rejectionReason: reason))
            lastCoveredOffset = offset + windowSize
        }
        return EEGIntervalAnalysisResult(channel: channel, windowSize: windowSize, hopSize: hopSize,
            windows: windows, frequenciesHz: (0...windowSize / 2).map { Double($0) * 128 / Double(windowSize) },
            meanDensityMicrovoltsSquaredPerHz: accepted > 0 ? sum.map { $0 / Double(accepted) } : nil,
            trailingUncoveredSampleCount: samples.count - lastCoveredOffset)
    }
}
