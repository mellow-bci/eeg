import Foundation

/// Comparison-only arithmetic from CortexService SQ bodies; not a deployed estimator.
/// Filtering, bands, learned Gaussian parameters and windowing are explicit external gates.
enum ReferenceSignalQualityKernel {
    enum Failure: Error { case unsupportedInput }
    struct Features: Equatable {
        let rms: Double
        let rmsDifference: Double
        let range: Double
    }
    struct Scores: Equatable {
        let transformedLogDensity: Double
        let gaussianState: Int
        let rmsState: Int
        let internalRMSState: Int
        let minimumContactState: Int
        let combinedState: Int
        let internalCombinedState: Int
    }

    /// Caller supplies a filtered channel window; maximumSamples is our support bound.
    /// Cortex detect 0x100c09c44..09d9c: differences x[j]-x[j+1], range max-min.
    static func features(_ samples: [Double], maximumSamples: Int) throws -> Features {
        guard maximumSamples >= 2, samples.count >= 2, samples.count <= maximumSamples,
              samples.allSatisfy({ $0.isFinite }) else { throw Failure.unsupportedInput }
        var energy = 0.0, differenceEnergy = 0.0
        var low = samples[0], high = samples[0]
        for i in samples.indices {
            let x = samples[i]
            energy = energy.addingProduct(x, x)
            low = min(low, x); high = max(high, x)
            if i + 1 < samples.count {
                let difference = x - samples[i + 1]
                differenceEnergy = differenceEnergy.addingProduct(difference, difference)
            }
        }
        let result = Features(rms: sqrt(energy / Double(samples.count)),
            rmsDifference: sqrt(differenceEnergy / Double(samples.count - 1)), range: high - low)
        guard result.rms.isFinite, result.rmsDifference.isFinite, result.range.isFinite
        else { throw Failure.unsupportedInput }
        return result
    }

    /// logDensity is the external Gaussian logPDF output, not an invented model score.
    /// Restrict to finite nonpositive density: positive/nonfinite logPDF has unresolved
    /// floating comparison/NaN behavior and is deliberately unsupported here.
    static func scores(logDensity: Double, rms: Double, scoreThresholds: [Double],
                       rmsThresholds: [Double], internalRMSThresholds: [Double],
                       contactStates: [Int], combineWithContact: Bool,
                       maximumContactStates: Int) throws -> Scores {
        guard logDensity.isFinite, logDensity <= 0, rms.isFinite, rms >= 0,
              scoreThresholds.count == 3, rmsThresholds.count == 2,
              internalRMSThresholds.count == 2,
              (scoreThresholds + rmsThresholds + internalRMSThresholds).allSatisfy({ $0.isFinite }),
              maximumContactStates >= 0, contactStates.count <= maximumContactStates,
              contactStates.allSatisfy({ (0...4).contains($0) })
        else { throw Failure.unsupportedInput }
        let transformed: Double
        let gaussian: Int
        if logDensity == 0 { transformed = 0; gaussian = 0 }
        else {
            transformed = log10(-logDensity)
            if transformed <= scoreThresholds[0] { gaussian = 4 }
            else if transformed <= scoreThresholds[1] { gaussian = 3 }
            else if transformed <= scoreThresholds[2] { gaussian = 1 }
            else { gaussian = 0 }
        }
        func amplitudeState(_ thresholds: [Double]) -> Int {
            if rms < thresholds[0] { return 0 }
            return rms <= thresholds[1] ? 4 : 1
        }
        let contact = contactStates.reduce(4, min)
        let amplitude = amplitudeState(rmsThresholds)
        let internalAmplitude = amplitudeState(internalRMSThresholds)
        var fused: Int
        if !combineWithContact { fused = min(gaussian, contact) }
        else if contact < 2 { fused = 0 }
        else if contact == 2 { fused = min(gaussian, 1) }
        else if contact == 4 && gaussian == 0 { fused = 1 }
        else { fused = min(gaussian, 2) + 2 }
        return Scores(transformedLogDensity: transformed, gaussianState: gaussian,
            rmsState: amplitude, internalRMSState: internalAmplitude,
            minimumContactState: contact, combinedState: min(fused, amplitude),
            internalCombinedState: min(fused, internalAmplitude))
    }
}
