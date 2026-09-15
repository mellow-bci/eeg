import Foundation

/// Exploratory cluster resampling, never physiological qualification or a proven
/// confidence interval. Whole session numerator/denominator pairs stay together.
public enum EEGSessionResampling {
    public struct Options: Codable, Sendable, Equatable {
        public var iterations: Int
        public var seed: UInt64
        public var centralMass: Double
        public init(iterations: Int = 10_000, seed: UInt64 = 0, centralMass: Double = 0.95) {
            self.iterations = iterations; self.seed = seed; self.centralMass = centralMass
        }
        public func validate() throws {
            guard iterations >= 2, centralMass.isFinite, centralMass > 0, centralMass < 1 else { throw Failure.invalidOptions }
        }
    }
    public struct Result: Codable, Sendable, Equatable {
        public let algorithm: String
        public let status: String
        public let sessionIDs: [String]
        public let options: Options
        public let lower: Double?, upper: Double?
    }
    public enum Failure: Error { case invalidOptions, invalidCounts }
    public static func run(_ sessions: [String: EEGLabeledEvaluation.TrialMetric], options: Options) throws -> Result {
        try options.validate()
        let ids = sessions.keys.sorted().filter { sessions[$0]!.declaredTrials > 0 }
        let rows = ids.map { sessions[$0]! }
        guard sessions.values.allSatisfy({ $0.declaredTrials >= 0 && $0.scoredTrials >= 0 &&
            $0.scoredTrials <= $0.declaredTrials && $0.observedTrials >= 0 && $0.observedTrials <= $0.scoredTrials }) else { throw Failure.invalidCounts }
        func result(_ status: String, _ lower: Double? = nil, _ upper: Double? = nil) -> Result {
            Result(algorithm: "session-pairs-percentile-v1", status: status, sessionIDs: ids, options: options, lower: lower, upper: upper)
        }
        guard rows.count >= 2 else { return result("insufficient_sessions") }
        guard rows.allSatisfy({ $0.unavailableTrials == 0 }) else { return result("incomplete_cue_evidence") }
        let rates = rows.map { Double($0.observedTrials) / Double($0.scoredTrials) }
        guard rates.min() != rates.max() else { return result("no_observed_session_variation") }
        var rng = Generator(state: options.seed), values = [Double]()
        // Explicit caller-selected work; no silent truncation or tier limit.
        for _ in 0..<options.iterations {
            try Task.checkCancellation()
            var observed = 0.0, scored = 0.0
            for _ in rows.indices {
                let row = rows[rng.index(count: rows.count)]
                observed += Double(row.observedTrials); scored += Double(row.scoredTrials)
            }
            values.append(observed / scored)
        }
        values.sort()
        guard values.first != values.last else { return result("degenerate_resamples") }
        let tail = (1 - options.centralMass) / 2
        return result("exploratory_only", quantile(values, tail), quantile(values, 1 - tail))
    }
    static func quantile(_ sorted: [Double], _ probability: Double) -> Double {
        let position = Double(sorted.count - 1) * probability
        let low = Int(position), high = min(low + 1, sorted.count - 1), fraction = position - Double(low)
        return sorted[low] + fraction * (sorted[high] - sorted[low])
    }
    /// SplitMix64 with rejection sampling for unbiased bounded indices.
    private struct Generator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9e3779b97f4a7c15
            var value = state
            value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
            value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
            return value ^ (value >> 31)
        }
        mutating func index(count: Int) -> Int {
            let bound = UInt64(count), threshold = (0 &- bound) % bound
            while true { let value = next(); if value >= threshold { return Int(value % bound) } }
        }
    }
}
