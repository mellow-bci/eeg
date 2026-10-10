import Foundation

/// Statically traced post-lowpass inference branch of ScoringManager::run.
/// This is NOT the vendor training/event lifecycle or a verified mental-command
/// detector. Inputs are ordered [trained neutral, actions..., appended neutral].
/// The caller owns one lowpass per row and must reset at recipe/profile changes.
/// See evidence/mental-command-reference/neutral-followup-20261010/README.md.
struct ReferenceCommandScoring {
    enum InputError: Error { case unsupportedConfiguration, invalidProbabilities }
    struct Output: Equatable {
        let action: Int
        let power: Double
        let activationThreshold: Double
    }

    let actions: [Int]
    let activationSetting: Int
    private(set) var isActivated = false

    init(actions: [Int], activationSetting: Int) throws {
        // Own deliberately bounded contract: the reference caller's local action
        // scratch space holds four IDs. We do not guess unsupported enum values.
        guard (1...4).contains(actions.count), Set(actions).count == actions.count,
              actions.allSatisfy({ $0 > 1 && $0 <= Int(Int32.max) }),
              (0...7).contains(activationSetting) else {
            throw InputError.unsupportedConfiguration
        }
        self.actions = actions
        self.activationSetting = activationSetting
    }

    var activationThreshold: Double {
        let scale = Double(bitPattern: 0x3fe199999999999a)
        let offset = Double(bitPattern: 0x3fd199999999999a)
        return ((3.5 - Double(activationSetting)) * scale / 7.0) + offset
    }

    mutating func reset() { isActivated = false }

    mutating func process(filteredProbabilities values: [Double]) throws -> Output {
        // Fail-closed validation is our policy, not a recovered vendor branch.
        guard values.count == actions.count + 2,
              values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            reset()
            throw InputError.invalidProbabilities
        }
        let threshold = activationThreshold
        func output(_ action: Int, _ power: Double) -> Output {
            Output(action: action, power: power, activationThreshold: threshold)
        }
        guard values[1..<(values.count - 1)].max()! >= threshold else {
            reset()
            return output(1, 0)
        }
        let identities = [1] + actions + [1]
        // Only the top two values affect power. Ties have zero positive margin
        // for this bounded nonnegative threshold, so tie ordering is immaterial.
        let ranked = values.indices.sorted { values[$0] > values[$1] }
        let winner = ranked[0]
        let margin = identities[winner] == 1 ? 0 : values[winner] - values[ranked[1]]
        let power = max(0, (margin - threshold) / (1 - threshold))
        if power == 0 {
            reset()
            return output(1, 0)
        }
        if power >= Double(bitPattern: 0x3fd3333333333333) {
            isActivated = true
        }
        guard isActivated else { return output(1, 0) }
        return output(identities[winner], power)
    }
}
