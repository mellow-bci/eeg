import Foundation

/// One-sided 95% Poisson mean bound, equivalent to chi2.ppf(.95,2*(k+1))/2.
/// Inverts P(X <= k | mean) = .05. Returns nil on invalid input/nonconvergence.
/// A constant independent event rate is an assumption, not a physiological finding.
enum EEGPoissonBound {
    static func upper95(count: Int) -> Double? {
        guard count >= 0, count < 9_007_199_254_740_991 else { return nil }
        if count == 0 { return -log(0.05) }
        let k = Double(count), target = log(0.05)
        func logCDF(_ mean: Double) -> Double? {
            guard mean >= k else { return nil }
            var term = 1.0, sum = 1.0, remaining = count
            var converged = false
            for _ in 0..<100000 {
                if remaining == 0 { converged = true; break }
                term *= Double(remaining) / mean; sum += term; remaining -= 1
                if term <= sum * 1e-15 { converged = true; break }
            }
            guard converged else { return nil }
            let logMass: Double
            if count < 16 { logMass = -mean + k * log(mean) - lgamma(k + 1) }
            else {
                // Stirling correction avoids subtracting enormous log-factorials.
                let inverse = 1 / k, square = inverse * inverse
                let correction = inverse * (1.0/12 - square * (1.0/360 - square * (1.0/1260 - square/1680)))
                let delta = mean - k
                logMass = k * log1p(delta / k) - delta - 0.5 * log(2 * .pi * k) - correction
            }
            let value = logMass + log(sum)
            return value.isFinite ? value : nil
        }
        var low = k, high = k + 4 * sqrt(k + 1) + 8
        guard let top = logCDF(high), top <= target else { return nil }
        for _ in 0..<100 {
            let middle = (low + high) / 2
            guard let value = logCDF(middle) else { return nil }
            if value > target { low = middle } else { high = middle }
            if high - low <= 1e-12 * high { return high }
        }
        return nil
    }
}
