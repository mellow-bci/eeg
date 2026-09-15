import Foundation

/// Conditional schedule-association calculation, not physiological validation.
/// Whole-trial outcomes are held fixed; no samples or windows are shuffled.
public enum EEGTrialPlanAssociation {
    public struct Result: Codable, Sendable, Equatable {
        public let algorithm: String
        public let status: String
        public let planSeed: String
        public let orderedTrialIDs: [String]
        public let candidateObserved: [Bool]
        public let observedTaskCandidateTrials: Int
        /// Index is the number of task-assigned trials with a candidate outcome.
        public let scheduleCountsByTaskCandidateTrials: [UInt64]
        public let admissibleSchedules: UInt64
        public let atLeastObservedSchedules: UInt64
        public var conditionalUpperTail: Double {
            Double(atLeastObservedSchedules) / Double(admissibleSchedules)
        }
    }
    public enum Failure: Error { case unsupportedPlan, incompleteOrExtraneousOutcomes }

    /// Requires one explicit outcome for every planned trial. The caller remains
    /// responsible for cue, completion, exposure and provenance qualification.
    /// Do not convert unavailable/rejected trials into false outcomes.
    public static func run(plan: EEGTrialPlan, candidateObserved: [String: Bool]) throws -> Result {
        try Task.checkCancellation()
        guard plan.controlProtocol == nil, plan.trials.count == 24,
              plan.trials.filter({ $0.requestedCondition == .neutral }).count == 12,
              plan.trials.filter({ $0.requestedCondition == .silentSerialSubtraction }).count == 12 else {
            throw Failure.unsupportedPlan
        }
        let ids = plan.trials.map(\.id)
        guard Set(ids).count == ids.count, Set(candidateObserved.keys) == Set(ids) else {
            throw Failure.incompleteOrExtraneousOutcomes
        }
        let outcomes = ids.map { candidateObserved[$0]! }
        let observed = zip(plan.trials, outcomes).filter {
            $0.0.requestedCondition == .silentSerialSubtraction && $0.1
        }.count
        let counts = try distribution(outcomes: outcomes, taskCount: 12,
                                      maximumRun: EEGTrialPlan.maximumConditionRun)
        let total = counts.reduce(0, +), tail = counts[observed...].reduce(0, +)
        return Result(algorithm: "trial-plan-conditional-association-v1",
            status: "conditional_only_exchangeability_unverified", planSeed: plan.seed,
            orderedTrialIDs: ids, candidateObserved: outcomes,
            observedTaskCandidateTrials: observed,
            scheduleCountsByTaskCandidateTrials: counts, admissibleSchedules: total,
            atLeastObservedSchedules: tail)
    }

    private struct State: Hashable {
        let tasks: Int, lastTask: Bool, run: Int, score: Int
    }
    /// Dynamic programming counts assignments, not Monte Carlo samples. Only
    /// called with the bounded v1 plan in production: <= C(24,12) assignments,
    /// safely below UInt64 capacity. Internal small cases support exhaustive tests.
    static func distribution(outcomes: [Bool], taskCount: Int, maximumRun: Int) throws -> [UInt64] {
        precondition(outcomes.count <= 24 && taskCount >= 0 && taskCount <= outcomes.count && maximumRun > 0)
        var states = [State(tasks: 0, lastTask: false, run: 0, score: 0): UInt64(1)]
        for (index, outcome) in outcomes.enumerated() {
            try Task.checkCancellation()
            var next = [State: UInt64]()
            for (state, count) in states {
                for task in [false, true] {
                    let tasks = state.tasks + (task ? 1 : 0)
                    let neutrals = index + 1 - tasks
                    let run = state.run > 0 && state.lastTask == task ? state.run + 1 : 1
                    guard tasks <= taskCount, neutrals <= outcomes.count - taskCount,
                          run <= maximumRun else { continue }
                    let key = State(tasks: tasks, lastTask: task, run: run,
                                    score: state.score + (task && outcome ? 1 : 0))
                    next[key, default: 0] += count
                }
            }
            states = next
        }
        var counts = [UInt64](repeating: 0, count: taskCount + 1)
        for (state, count) in states where state.tasks == taskCount { counts[state.score] += count }
        return counts
    }
}
