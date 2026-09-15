import Foundation

/// Independent, reproducible order generation for the documented v1 protocol.
public struct EEGTrialPlan: Encodable, Sendable {
    public static let maximumConditionRun = 3
    public let schema = "eeg.trial-plan.v1"
    public let algorithm = "splitmix64-fisher-yates-rejection-v1"
    public let controlProtocol: String?
    public let seed: String
    public let trials: [EEGTrialEvidence]
    public init(sessionID: String, participantID: String, seed: UInt64, controls: Bool = false) throws {
        controlProtocol = controls ? "eeg.artifact-controls.v1" : nil
        var rng = Generator(state: seed)
        var conditions = [EEGTrialEvidence.Condition]()
        for _ in 0..<10000 {
            var proposal: [EEGTrialEvidence.Condition] = controls
                ? [.ordinaryActivity, .blinkControl, .jawControl, .headMovementControl].flatMap { Array(repeating:$0,count:6) }
                : Array(repeating:.neutral,count:12) + Array(repeating:.silentSerialSubtraction,count:12)
            for i in stride(from: proposal.count-1, through: 1, by: -1) {
                proposal.swapAt(i, rng.bounded(i+1))
            }
            if !(Self.maximumConditionRun..<proposal.count).contains(where: { i in (1...Self.maximumConditionRun).allSatisfy { proposal[i] == proposal[i-$0] } }) {
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
    public static func recover(_ data: Data) throws -> EEGTrialPlan {
        guard data.count <= 4 * 1024 * 1024,
              let value=try JSONSerialization.jsonObject(with:data) as? [String:Any],
              let seed=value["seed"] as? String,let number=UInt64(seed),
              let trials=value["trials"] as? [[String:Any]],let first=trials.first,
              let session=first["sessionID"] as? String,let participant=first["participantID"] as? String else { throw EEGTrialEvidence.Failure.invalidTransition }
        let plan=try EEGTrialPlan(sessionID:session,participantID:participant,seed:number,controls:value["controlProtocol"] as? String == "eeg.artifact-controls.v1")
        let expected=try JSONSerialization.jsonObject(with:JSONEncoder().encode(plan))
        guard try JSONSerialization.data(withJSONObject:expected,options:[.sortedKeys]) == JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]) else { throw EEGTrialEvidence.Failure.invalidTransition }
        return plan
    }
    /// Enforces a conservative minimum after review, which follows the report.
    /// Every eighth trial gets a full minute; an interruption consumes its slot.
    public func next(after completed: EEGTrialEvidence?, started: Int, at: Double) throws -> EEGTrialEvidence {
        guard at.isFinite,at >= 0,started >= 0,started < trials.count else { throw EEGTrialEvidence.Failure.invalidTime }
        guard at >= (try earliestNextStart(after: completed, started: started)) else { throw EEGTrialEvidence.Failure.readinessMissing }
        return trials[started]
    }
    /// Earliest permitted start on the recording clock; shared with the native countdown.
    public func earliestNextStart(after completed: EEGTrialEvidence?, started: Int) throws -> Double {
        guard started >= 0, started < trials.count else { throw EEGTrialEvidence.Failure.invalidTransition }
        if started > 0 {
            guard let completed,completed.id == trials[started-1].id,
                  completed.phase == .reviewed || completed.phase == .interrupted,
                  let last = completed.events.last else { throw EEGTrialEvidence.Failure.invalidTransition }
            let rest: Double = started % 8 == 0 ? 60 : 10
            return last.at + rest
        } else if completed != nil { throw EEGTrialEvidence.Failure.invalidTransition }
        return 0
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
