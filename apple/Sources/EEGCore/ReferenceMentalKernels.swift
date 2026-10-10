import Foundation

/// Bounded, statically traced arithmetic, not a complete Cortex classifier.
/// See docs/MENTAL_KERNEL_PARITY.md. Deliberately not enabled for existing profiles.
enum ReferenceMentalKernels {
    enum InputError: Error { case invalidWindowLength, nonFiniteInput }

    /// Classifier constructor selects WindowingTxf mode 1: symmetric Hamming.
    /// Reject N < 2 rather than reproducing the reference's N=1 division by zero.
    static func hamming(count: Int) throws -> [Double] {
        guard count >= 2, count <= Int(Int32.max) else {
            throw InputError.invalidWindowLength
        }
        let tau = Double(bitPattern: 0x401921fb54442d18)
        let offset = Double(bitPattern: 0x3fe147ae147ae148)
        let factor = Double(bitPattern: 0xbfdd70a3d70a3d71)
        return (0..<count).map {
            let phase = (Double($0) * tau) / Double(count - 1)
            return offset.addingProduct(cos(phase), factor)
        }
    }

    /// One time series; callers keep channel/time orientation explicit.
    static func window(_ samples: [Double]) throws -> [Double] {
        guard samples.allSatisfy(\.isFinite) else { throw InputError.nonFiniteInput }
        let coefficients = try hamming(count: samples.count)
        return zip(samples, coefficients).map(*)
    }
}

/// Order-1 kernel selected by ScoringManager::setLPF, including first-input
/// history initialization. Own API policies: empty blocks are no-ops and invalid
/// blocks reject atomically. No probability threshold or command meaning implied.
struct ReferenceScoringLowpass {
    private var previousInput: Double?
    private var previousOutput: Double?

    mutating func reset() {
        previousInput = nil
        previousOutput = nil
    }

    mutating func process(_ samples: [Double]) throws -> [Double] {
        guard samples.allSatisfy(\.isFinite) else {
            throw ReferenceMentalKernels.InputError.nonFiniteInput
        }
        var output: [Double] = []
        output.reserveCapacity(samples.count)
        for sample in samples {
            let priorInput = previousInput ?? sample
            let priorOutput = previousOutput ?? sample
            // Preserve the traced FMADD, FMADD, FMSUB accumulation order.
            var value = 0.0.addingProduct(0.2, sample)
            value = value.addingProduct(0.0, priorInput)
            value = value.addingProduct(0.8, priorOutput)
            output.append(value)
            previousInput = sample
            previousOutput = value
        }
        return output
    }
}
