import Foundation

/// Explicit-parameter reconstruction of bounded Cortex classifier arithmetic.
/// Not connected to runtime profiles: learned parameters, front-end recipe and
/// caller semantics still require independent training and reference validation.
/// Body evidence: evidence/mental-command-reference/gaussian-followup-20261010.
enum ReferenceGaussianPipeline {
    enum InputError: Error, Equatable {
        case invalidShape, nonFiniteInput, invalidWeight, nonPositiveDefiniteCovariance
        case invalidClassCount, invalidNormalization, numericalFailure
    }

    struct CenteredTransform: Sendable, Codable {
        let mean: [Double]
        /// Row-major: input feature rows, output component columns.
        let basis: [[Double]]
    }

    struct Component: Sendable, Codable {
        let weight: Double
        let mean: [Double]
        /// Full covariance, not the independent classifier's diagonal variances.
        let covariance: [[Double]]
    }

    struct Mixture: Sendable, Codable { let components: [Component] }

    struct Parameters: Sendable, Codable {
        let pca: CenteredTransform
        let canonical: CenteredTransform
        /// Traced canonical routine selects the first K-1 columns for K >= 2.
        let canonicalClassCount: Int
        let classes: [Mixture]
        let classPriors: [Double]
        /// Caller-supplied scalar; no fabricated default or sensitivity conversion.
        let neutralScale: Double
    }

    struct Result: Sendable {
        let pcaFeatures: [Double]
        let canonicalFeatures: [Double]
        let classDensity: [Double]
        let classPeakDensity: [Double]
        /// Class slots followed by the appended slot. Its application label and
        /// decision threshold are the caller's responsibility, not inferred here.
        let posterior: [Double]
    }

    struct Density: Sendable {
        let value: Double
        let atMean: Double
        let logValue: Double
    }

    static func infer(featureVector: [Double], parameters: Parameters) throws -> Result {
        let pca = try transform(featureVector, using: parameters.pca)
        let canonical = try canonicalTransform(pca, using: parameters.canonical,
                                               classCount: parameters.canonicalClassCount)
        guard !parameters.classes.isEmpty,
              parameters.classPriors.count == parameters.classes.count else {
            throw InputError.invalidShape
        }
        var density: [Double] = []
        var peak: [Double] = []
        for mixture in parameters.classes {
            let values = try mixtureDensity(canonical, mixture: mixture)
            density.append(values.value)
            peak.append(values.atMean)
        }
        let posterior = try posterior(density: density, peakDensity: peak,
                                      priors: parameters.classPriors, neutralScale: parameters.neutralScale)
        return Result(pcaFeatures: pca, canonicalFeatures: canonical,
                      classDensity: density, classPeakDensity: peak, posterior: posterior)
    }

    /// 0x100b1e9cc -> same-shape subtract 0x100b20928 -> matmul 0x100b22ea8.
    static func transform(_ input: [Double], using transform: CenteredTransform) throws -> [Double] {
        guard !input.isEmpty, transform.mean.count == input.count,
              transform.basis.count == input.count,
              let count = transform.basis.first?.count, count > 0,
              transform.basis.allSatisfy({ $0.count == count }) else { throw InputError.invalidShape }
        guard input.allSatisfy(\.isFinite), transform.mean.allSatisfy(\.isFinite),
              transform.basis.allSatisfy({ $0.allSatisfy(\.isFinite) }) else { throw InputError.nonFiniteInput }
        let centered = zip(input, transform.mean).map(-)
        guard centered.allSatisfy(\.isFinite) else { throw InputError.numericalFailure }
        let output = (0..<count).map { column in
            centered.indices.reduce(0.0) { $0.addingProduct(centered[$1], transform.basis[$1][column]) }
        }
        guard output.allSatisfy(\.isFinite) else { throw InputError.numericalFailure }
        return output
    }

    /// 0x100b1ecfc..0x100b1ee00: select columns [0, K-2] before matmul.
    static func canonicalTransform(_ input: [Double], using transform: CenteredTransform,
                                   classCount: Int) throws -> [Double] {
        guard classCount >= 1 else { throw InputError.invalidClassCount } // Own policy for K=0.
        guard let columns = transform.basis.first?.count, columns > 0,
              transform.basis.allSatisfy({ $0.count == columns }) else { throw InputError.invalidShape }
        if classCount == 1 { return try self.transform(input, using: transform) }
        guard classCount - 1 <= columns else { throw InputError.invalidShape }
        let selected = CenteredTransform(mean: transform.mean,
                                        basis: transform.basis.map { Array($0.prefix(classCount - 1)) })
        return try self.transform(input, using: selected)
    }

    /// Traced MvnpdfTxf: upper Cholesky R, z=(x-mu)*inv(R),
    /// c=sqrt((2*pi)^(-D))/prod(diag(R)), pdf=c*exp(-||z||^2/2).
    /// We use the equivalent lower-triangular solve instead of explicitly forming
    /// the inverse. This is algebraically equivalent, not bit-identical LAPACK.
    /// Strict finite, symmetric SPD inputs are OUR support boundary; no ridge,
    /// pseudoinverse, diagonal approximation or hidden repair is substituted.
    static func gaussianDensity(_ input: [Double], component: Component) throws -> Density {
        let count = input.count
        guard count > 0, component.mean.count == count, component.covariance.count == count,
              component.covariance.allSatisfy({ $0.count == count }) else { throw InputError.invalidShape }
        guard input.allSatisfy(\.isFinite), component.mean.allSatisfy(\.isFinite),
              component.covariance.allSatisfy({ $0.allSatisfy(\.isFinite) }) else {
            throw InputError.nonFiniteInput
        }
        for row in 0..<count {
            for column in 0..<row where component.covariance[row][column] != component.covariance[column][row] {
                throw InputError.nonPositiveDefiniteCovariance
            }
        }
        var lower = Array(repeating: Array(repeating: 0.0, count: count), count: count)
        for row in 0..<count {
            for column in 0...row {
                var residual = component.covariance[row][column]
                for k in 0..<column { residual -= lower[row][k] * lower[column][k] }
                guard residual.isFinite else { throw InputError.numericalFailure }
                if row == column {
                    guard residual > 0 else { throw InputError.nonPositiveDefiniteCovariance }
                    lower[row][column] = sqrt(residual)
                } else {
                    lower[row][column] = residual / lower[column][column]
                }
            }
        }
        var z = Array(repeating: 0.0, count: count)
        var diagonalProduct = 1.0
        for row in 0..<count {
            var residual = input[row] - component.mean[row]
            for column in 0..<row { residual -= lower[row][column] * z[column] }
            z[row] = residual / lower[row][row]
            diagonalProduct *= lower[row][row]
        }
        let squaredDistance = z.reduce(0.0) { $0 + $1 * $1 }
        let tau = Double(bitPattern: 0x401921fb54442d18)
        let peak = sqrt(pow(tau, -Double(count))) * (1.0 / diagonalProduct)
        let value = peak * exp(-0.5 * squaredDistance)
        let logValue = log(peak) - 0.5 * squaredDistance
        guard squaredDistance.isFinite, peak.isFinite, peak > 0, value.isFinite, logValue.isFinite else {
            throw InputError.numericalFailure
        }
        return Density(value: value, atMean: peak, logValue: logValue)
    }

    /// 0x100b1f170..0x100b1f254 evaluates each component at input AND its own
    /// mean, accumulating both with its supplied weight. We do not renormalize.
    static func mixtureDensity(_ input: [Double], mixture: Mixture) throws -> Density {
        guard !mixture.components.isEmpty else { throw InputError.invalidShape }
        guard mixture.components.allSatisfy({ $0.weight.isFinite && $0.weight >= 0 }),
              mixture.components.contains(where: { $0.weight > 0 }) else { throw InputError.invalidWeight }
        var value = 0.0
        var peak = 0.0
        for component in mixture.components {
            let density = try gaussianDensity(input, component: component)
            value = value.addingProduct(density.value, component.weight)
            peak = peak.addingProduct(density.atMean, component.weight)
        }
        guard value.isFinite, peak.isFinite, peak > 0 else { throw InputError.numericalFailure }
        // A zero likelihood from exp underflow is allowed here; posterior checks
        // that at least one supported slot retains positive probability mass.
        return Density(value: value, atMean: peak, logValue: log(value))
    }

    /// 0x100b1f48c: first density column * caller prior, then append
    /// min(second/peak column)*scalar; divide ALL slots by their total.
    /// Finite, nonnegative and positive-total checks are independent safety policy.
    static func posterior(density: [Double], peakDensity: [Double], priors: [Double],
                          neutralScale: Double) throws -> [Double] {
        guard !density.isEmpty, density.count == peakDensity.count,
              density.count == priors.count else { throw InputError.invalidShape }
        guard (density + peakDensity + priors + [neutralScale]).allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw InputError.invalidNormalization
        }
        var mass = zip(density, priors).map(*)
        mass.append(peakDensity.min()! * neutralScale)
        let total = mass.reduce(0, +)
        guard mass.allSatisfy(\.isFinite), total.isFinite, total > 0 else { throw InputError.invalidNormalization }
        return mass.map { $0 / total }
    }
}
