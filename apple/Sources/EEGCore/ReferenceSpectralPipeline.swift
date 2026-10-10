import Foundation

/// Bounded spectral arithmetic reconstructed from static Cortex bodies.
/// Independent radix-2 implementation; not a bit-identical vendor FFT.
/// Input is explicitly one already-preprocessed time series, not raw headset data.
enum ReferenceSpectralPipeline {
    enum InputError: Error { case invalidInput, numericalFailure }
    struct Band: Sendable, Codable { let lowerHz: Double; let upperHz: Double }

    /// Median across matrix rows at each column, then broadcast subtraction.
    /// Caller must supply the actual selected-row order; no raw device mapping
    /// is inferred here. Sorting is our implementation of the traced reduction.
    static func preprocess(_ matrix: [[Double]]) throws -> [[Double]] {
        guard !matrix.isEmpty, let columns = matrix.first?.count, columns > 0,
              matrix.allSatisfy({ $0.count == columns && $0.allSatisfy(\.isFinite) }) else {
            throw InputError.invalidInput
        }
        var output = matrix
        for column in 0..<columns {
            let sorted = matrix.map { $0[column] }.sorted()
            let middle = sorted.count / 2
            let median: Double
            if sorted.count % 2 == 1 { median = sorted[middle] }
            else { median = sorted[middle] + (sorted[middle - 1] - sorted[middle]) * 0.5 }
            for row in matrix.indices { output[row][column] -= median }
        }
        guard output.allSatisfy({ $0.allSatisfy(\.isFinite) }) else { throw InputError.numericalFailure }
        return output
    }

    /// FFT_Txf(2,true), complex multiply by 2, Complex2Real(0,false).
    /// Includes DC; excludes Nyquist. No implicit padding or windowing.
    static func spectrum(_ samples: [Double]) throws -> [Double] {
        let n = samples.count
        guard n >= 2, n & (n - 1) == 0, samples.allSatisfy(\.isFinite) else {
            throw InputError.invalidInput
        }
        var real = samples
        var imaginary = Array(repeating: 0.0, count: n)
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 { j ^= bit; bit >>= 1 }
            j ^= bit
            if i < j { real.swapAt(i, j) }
        }
        var width = 2
        while width <= n {
            for start in stride(from: 0, to: n, by: width) {
                for k in 0..<(width / 2) {
                    let phase = -2 * Double.pi * Double(k) / Double(width)
                    let c = cos(phase), s = sin(phase)
                    let a = start + k, b = a + width / 2
                    let r = real[b] * c - imaginary[b] * s
                    let im = real[b] * s + imaginary[b] * c
                    real[b] = real[a] - r; imaginary[b] = imaginary[a] - im
                    real[a] += r; imaginary[a] += im
                }
            }
            if width == n { break }
            width *= 2
        }
        let output = (0..<(n / 2)).map { index -> Double in
            let r = real[index] / Double(n) * 2
            let im = imaginary[index] / Double(n) * 2
            return (im * im).addingProduct(r, r)
        }
        guard output.allSatisfy(\.isFinite) else { throw InputError.numericalFailure }
        return output
    }

    /// BandPower mode 0 is MEAN, not sum. Inclusive ceil endpoints, upper
    /// clamped to last bin; channelBandTransform then doubles each result.
    static func bands(_ spectrum: [Double], sampleRate: Double, bands: [Band]) throws -> [Double] {
        guard !spectrum.isEmpty, sampleRate.isFinite, sampleRate > 0,
              spectrum.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw InputError.invalidInput }
        let spacing = sampleRate / (2 * Double(spectrum.count))
        guard spacing.isFinite, spacing > 0 else { throw InputError.invalidInput }
        return try bands.map { band in
            guard band.lowerHz.isFinite, band.upperHz.isFinite,
                  band.lowerHz >= 0, band.upperHz >= band.lowerHz,
                  band.upperHz <= sampleRate / 2 else { throw InputError.invalidInput }
            let lower = Int(ceil(band.lowerHz / spacing))
            let upper = min(spectrum.count - 1, Int(ceil(band.upperHz / spacing)))
            guard lower <= upper else { throw InputError.invalidInput }
            var even = 0.0, odd = 0.0
            for i in lower...upper {
                if (i - lower) % 2 == 0 { even += spectrum[i] } else { odd += spectrum[i] }
            }
            let result = (odd + even) / Double(upper - lower + 1) * 2
            guard result.isFinite else { throw InputError.numericalFailure }
            return result
        }
    }
}
