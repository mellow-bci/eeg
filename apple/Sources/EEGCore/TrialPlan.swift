import Foundation

/// Independent, reproducible order generation for the documented v1 protocol.
public struct EEGTrialPlan: Encodable, Sendable {
    public let schema = "eeg.trial-plan.v1"
    public let algorithm = "splitmix64-fisher-yates-rejection-v1"
    public let seed: String
    public let trials: [EEGTrialEvidence]
    public init(sessionID: String, participantID: String, seed: UInt64) throws {
        var rng = Generator(state: seed)
        var conditions = [EEGTrialEvidence.Condition]()
        for _ in 0..<10000 {
            var proposal = Array(repeating: EEGTrialEvidence.Condition.neutral, count: 12)
                + Array(repeating: EEGTrialEvidence.Condition.silentSerialSubtraction, count: 12)
            for i in stride(from: proposal.count-1, through: 1, by: -1) {
                proposal.swapAt(i, rng.bounded(i+1))
            }
            if !(3..<proposal.count).contains(where: { i in (1...3).allSatisfy { proposal[i] == proposal[i-$0] } }) {
                conditions = proposal; break
            }
        }
        guard conditions.count == 24 else { throw EEGTrialEvidence.Failure.invalidTransition }
        self.seed = String(seed)
        trials = try conditions.enumerated().map { index, condition in
            try EEGTrialEvidence(id: "\(sessionID)-trial-\(index+1)", sessionID: sessionID,
                participantID: participantID, condition: condition, startingNumber: 100+rng.bounded(900))
        }
    }
    /// Enforces a conservative minimum after review, which follows the report.
    /// Every eighth trial gets a full minute; an interruption consumes its slot.
    public func next(after completed: EEGTrialEvidence?, started: Int, at: Double) throws -> EEGTrialEvidence {
        guard at.isFinite,at >= 0,started >= 0,started < trials.count else { throw EEGTrialEvidence.Failure.invalidTime }
        if started > 0 {
            guard let completed,completed.id == trials[started-1].id,
                  completed.phase == .reviewed || completed.phase == .interrupted,
                  let last = completed.events.last else { throw EEGTrialEvidence.Failure.invalidTransition }
            let rest: Double = started % 8 == 0 ? 60 : 10
            guard at >= last.at+rest else { throw EEGTrialEvidence.Failure.readinessMissing }
        } else if completed != nil { throw EEGTrialEvidence.Failure.invalidTransition }
        return trials[started]
    }
    private struct Generator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9e3779b97f4a7c15
            var z = state
            z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
            z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
            return z ^ (z >> 31)
        }
        mutating func bounded(_ bound: Int) -> Int {
            let n = UInt64(bound), threshold = (0 &- n) % n
            while true { let value = next(); if value >= threshold { return Int(value % n) } }
        }
    }
}
