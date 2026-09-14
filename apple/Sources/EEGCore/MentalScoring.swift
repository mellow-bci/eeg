import Foundation

/// Numerical kernel for our independent classifier, not a profile loader or an
/// authorization gate. Callers still need validated provenance and valid windows.
public struct EEGMentalScoringParameters: Decodable, Sendable {
    public struct Gaussian: Decodable, Sendable {
        public let label: String
        public let mean: [Double]
        public let variance: [Double]
        public let distance_limit: Double
    }
    public let classes: [String]
    public let center: [Double]
    public let scale: [Double]
    public let selected: [Int]
    public let pca_mean: [Double]
    public let components: [[Double]]
    public let gaussians: [Gaussian]
}

public struct EEGMentalScore: Sendable {
    public let labels: [String]
    public let uncalibratedScores: [Double]
    public let squaredDistances: [Double]
    public let bestIndex: Int
    public var candidateLabel: String { labels[bestIndex] }
    public let outsideTrainingDistribution: Bool
    // This is deliberately a numerical result, not a command proposal.
}

public enum EEGMentalScoringError: Error { case invalidParameters, invalidFeatures, numericalFailure }

public enum EEGMentalScoring {
    public static func score(values: [Double], parameters p: EEGMentalScoringParameters) throws -> EEGMentalScore {
        let width = EEGMentalFeatures.names.count
        let k = p.selected.count, d = p.components.count
        func finite(_ values: [Double]) -> Bool { values.allSatisfy(\.isFinite) }
        guard p.classes.count >= 2, Set(p.classes).count == p.classes.count,
              p.classes.contains("neutral"), p.classes.allSatisfy({ !$0.isEmpty }),
              p.center.count == width, p.scale.count == width, finite(p.center), finite(p.scale),
              p.scale.allSatisfy({ $0 > 0 }), k > 0, k <= width,
              Set(p.selected).count == k, p.selected.allSatisfy({ (0..<width).contains($0) }),
              p.pca_mean.count == k, finite(p.pca_mean), d > 0, d <= k,
              p.components.allSatisfy({ $0.count == k && finite($0) }),
              p.gaussians.count == p.classes.count else { throw EEGMentalScoringError.invalidParameters }
        for (label, g) in zip(p.classes, p.gaussians) {
            guard g.label == label, g.mean.count == d, g.variance.count == d,
                  finite(g.mean), finite(g.variance), g.variance.allSatisfy({ $0 > 0 }),
                  g.distance_limit.isFinite, g.distance_limit > 0 else { throw EEGMentalScoringError.invalidParameters }
        }
        guard values.count == width, finite(values) else { throw EEGMentalScoringError.invalidFeatures }
        let z = p.selected.enumerated().map { offset, index in
            (values[index] - p.center[index]) / p.scale[index] - p.pca_mean[offset]
        }
        let projected = p.components.map { row in zip(z, row).reduce(0.0) { $0 + $1.0 * $1.1 } }
        guard finite(z), finite(projected) else { throw EEGMentalScoringError.numericalFailure }
        var distances = [Double](), logScores = [Double]()
        for g in p.gaussians {
            let distance = (0..<d).reduce(0.0) { sum, i in
                let delta = projected[i] - g.mean[i]
                return sum + delta * delta / g.variance[i]
            }
            let score = -0.5 * (distance + g.variance.reduce(0.0) { $0 + log(2 * Double.pi * $1) })
            guard distance.isFinite, score.isFinite else { throw EEGMentalScoringError.numericalFailure }
            distances.append(distance); logScores.append(score)
        }
        let peak = logScores.max()!
        let weights = logScores.map { exp($0 - peak) }
        let total = weights.reduce(0, +)
        guard total.isFinite, total > 0 else { throw EEGMentalScoringError.numericalFailure }
        let probabilities = weights.map { $0 / total }
        // Stable first-class selection on ties; ambiguity rejection belongs to the detector.
        let best = probabilities.indices.reduce(0) { probabilities[$1] > probabilities[$0] ? $1 : $0 }
        return EEGMentalScore(labels: p.classes, uncalibratedScores: probabilities,
                              squaredDistances: distances, bestIndex: best,
                              outsideTrainingDistribution: distances[best] > p.gaussians[best].distance_limit)
    }
}
