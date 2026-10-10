import Foundation

/// Comparison-only lifecycle from runAutoSamplingNeutral (0x100b31608).
/// Epochs are Matrix objects, not samples. The caller supplies the traced
/// validity flag; its upstream derivation is not yet recovered.
struct ReferenceNeutralTraining {
    typealias Matrix = [[Double]]
    struct Epoch: Equatable {
        let primary: Matrix
        let secondary: Matrix
    }
    enum InputError: Error, Equatable {
        case invalidConfiguration, unsupportedControl, invalidMatrix, bufferCapacity
    }
    enum FitResult: Equatable {
        case saved
        /// Traced failure clears classifier and attempts to save the empty bank.
        case buildFailed(emptyBankSaved: Bool)
        /// Successful build followed by failed save does not clear the classifier.
        case saveFailed
    }
    enum Completion: Equatable {
        case insufficientEpochs(collected: Int, required: Int)
        case fitted(FitResult)
    }
    struct Transition: Equatable {
        var lockSettings = false
        var appended = false
        var completion: Completion? = nil
        var unlockSettings = false
        var clearClassifierErrorsAndUpdateActions = false
        var event: Int? = nil
        var autoSamplingValue: Int? = nil
        var trainingAction: Int? = nil
    }
    let minimumEpochs: Int
    /// Our explicit resource policy; not a recovered Cortex parameter.
    let maximumBufferedEpochs: Int
    private(set) var collecting = false
    private(set) var epochs = [Epoch]()

    init(minimumEpochs: Int, maximumBufferedEpochs: Int) throws {
        guard minimumEpochs > 0, maximumBufferedEpochs >= minimumEpochs else {
            throw InputError.invalidConfiguration
        }
        self.minimumEpochs = minimumEpochs
        self.maximumBufferedEpochs = maximumBufferedEpochs
    }

    /// fit must actually build/save, and report both outcomes. It receives the
    /// neutral action (1) and the paired buffers; no simulated success default.
    mutating func advance(autoSampling: Int, trainingControl: Int, valid: Bool,
                          primary: Matrix, secondary: Matrix,
                          fit: ([Epoch], Int) -> FitResult) throws -> Transition {
        let effective = autoSampling == 1 && trainingControl == 1 ? 0 : autoSampling
        guard effective == 0 || effective == 1 else { throw InputError.unsupportedControl }
        if effective == 1 {
            // Our finite/rectangular and capacity checks are atomic. Cortex's
            // body only checks validity and primary isEmpty before appending.
            let append = valid && !primary.isEmpty && primary.contains(where: { !$0.isEmpty })
            if append {
                guard Self.validMatrix(primary), Self.validMatrix(secondary) else { throw InputError.invalidMatrix }
                guard epochs.count < maximumBufferedEpochs else { throw InputError.bufferCapacity }
            }
            collecting = true
            if append { epochs.append(Epoch(primary: primary, secondary: secondary)) }
            return Transition(lockSettings: true, appended: append)
        }
        guard collecting else { return Transition() }
        collecting = false
        let completion: Completion
        let attempted = epochs.count >= minimumEpochs
        if attempted { completion = .fitted(fit(epochs, 1)) }
        else { completion = .insufficientEpochs(collected: epochs.count, required: minimumEpochs) }
        epochs.removeAll(keepingCapacity: false)
        // Event 8 is emitted even when insufficient: it is completion, not proof
        // of a trained classifier. Unlocking and autoSampling=0 always follow.
        return Transition(completion: completion, unlockSettings: true,
                          clearClassifierErrorsAndUpdateActions: attempted,
                          event: 8, autoSamplingValue: 0,
                          trainingAction: attempted ? 1 : nil)
    }

    /// resetTrainingState clears collection and sets auto=0, action=1, control=0.
    mutating func reset() -> (autoSampling: Int, action: Int, control: Int) {
        collecting = false
        epochs.removeAll(keepingCapacity: false)
        return (0, 1, 0)
    }

    private static func validMatrix(_ value: Matrix) -> Bool {
        guard let width = value.first?.count else { return true }
        return value.allSatisfy { $0.count == width && $0.allSatisfy(\.isFinite) }
    }
}
