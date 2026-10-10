import Foundation

/// Pure comparison-only profile updates. No database/profile export is implied.
enum ReferenceTrainingProfileUpdates {
    enum InputError: Error, Equatable {
        case invalidActionCatalogue, unknownAction, invalidCounts, invalidExistenceFlags, capacityExceeded
    }

    /// Catalogue order defines count columns explicitly; no action-ID/column map is guessed.
    /// nil counts means property absent. nil trainedActions means that property absent.
    static func countTraining(action: Int32, actionColumns: [Int32],
                              existingCounts: [Double]?, trainedActions: [Int32]?,
                              maximumActions: Int) throws -> [Double] {
        try validateCatalogue(actionColumns, maximumActions: maximumActions)
        guard let column = actionColumns.firstIndex(of: action) else { throw InputError.unknownAction }
        if var counts = existingCounts {
            guard counts.count == actionColumns.count,
                  counts.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw InputError.invalidCounts }
            counts[column] += 1
            guard counts[column].isFinite, counts[column] > existingCounts![column] else { throw InputError.invalidCounts }
            return counts
        }
        var counts = Array(repeating: 0.0, count: actionColumns.count)
        if let trainedActions {
            guard trainedActions.count <= maximumActions else { throw InputError.capacityExceeded }
            let trained = Set(trainedActions)
            for (index, candidate) in actionColumns.enumerated() where trained.contains(candidate) {
                counts[index] = candidate == action ? 2 : 1
            }
        } else {
            counts[column] = 1
        }
        return counts
    }

    /// DB existence is an explicit observed input, not inferred from count or signal quality.
    /// Existing surviving entries retain order (and duplicates); new IDs append in catalogue order.
    static func updateTrainedActions(actionCatalogue: [Int32], dataExists: [Bool],
                                     existingActions: [Int32], maximumActions: Int) throws -> [Int32] {
        try validateCatalogue(actionCatalogue, maximumActions: maximumActions)
        guard dataExists.count == actionCatalogue.count else { throw InputError.invalidExistenceFlags }
        guard existingActions.count <= maximumActions else { throw InputError.capacityExceeded }
        let available = zip(actionCatalogue, dataExists).compactMap { $0.1 ? $0.0 : nil }
        let availableSet = Set(available)
        var result = existingActions.filter { availableSet.contains($0) }
        var present = Set(result)
        for action in available where !present.contains(action) {
            guard result.count < maximumActions else { throw InputError.capacityExceeded }
            result.append(action)
            present.insert(action)
        }
        return result
    }

    private static func validateCatalogue(_ actions: [Int32], maximumActions: Int) throws {
        guard maximumActions > 0, actions.count <= maximumActions else { throw InputError.capacityExceeded }
        guard !actions.isEmpty, actions.allSatisfy({ $0 >= 0 }), Set(actions).count == actions.count else {
            throw InputError.invalidActionCatalogue
        }
    }
}
