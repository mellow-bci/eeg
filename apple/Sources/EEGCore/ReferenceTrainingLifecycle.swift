import Foundation

/// Static-body comparison model of runTraining, not the production live trainer.
/// Profile settings and upstream epoch validity are explicit inputs. Fitting,
/// persistence and reset/rebuild must be provided by a real caller.
struct ReferenceTrainingLifecycle {
    typealias Epoch = ReferenceNeutralTraining.Epoch
    typealias FitResult = ReferenceNeutralTraining.FitResult
    enum InputError: Error { case configuration, control, invalidInput, clockRegression, sampleOverflow }
    struct Configuration {
        let samplingRate: UInt64
        let stepSamples: UInt64
        let startAfterSeconds: Float
        let trainingSeconds: Float
        let minimumEpochs: Int
        let maximumEpochs: Int
    }
    struct Transition {
        var event: Int? = nil
        var completed = false
        var lockSettings = false
        var unlockSettings = false
        var unlockTrainingControlOnly = false
        var incrementTrainingAttempts = false
        var appended = false
        var droppedOldest = false
        var fitResult: FitResult? = nil
        var clearErrors = false
        var updateActions = false
        var updateTrainingCount = false
        var thresholdAndScore: (Double, Double)? = nil
    }
    let configuration: Configuration
    private(set) var epochs: [Epoch] = []
    private(set) var active = false
    private(set) var samples: UInt64 = 0
    private(set) var startedEvent = false
    private(set) var completionEvent = false
    private(set) var timerOriginMilliseconds: Int64? = nil
    private var previousClock: Int64? = nil

    init(configuration: Configuration) throws {
        guard configuration.samplingRate > 0, configuration.stepSamples > 0,
              configuration.startAfterSeconds.isFinite, configuration.trainingSeconds.isFinite,
              configuration.startAfterSeconds >= 0,
              configuration.trainingSeconds >= configuration.startAfterSeconds,
              configuration.minimumEpochs > 0,
              configuration.maximumEpochs >= configuration.minimumEpochs,
              (configuration.trainingSeconds + 1.5).isFinite else { throw InputError.configuration }
        self.configuration = configuration
    }

    /// control jump-table bytes18,1c,0e,00,3c,00 at102647f98 map
    /// 0 idle,1 collect,2 accept,3 reject(event6),4 reset,5 complete(event7).
    /// Event4 is acceptance notification even if fit/save fails.
    /// Reset's bank/cache/brain-map mutations remain caller-owned; no mock default.
    mutating func advance(control: Int, action: Int, activeActionCount: Int,
                          actionPreviouslyTrained: Bool, scoringHistory: [Double],
                          valid: Bool, primary: [[Double]], secondary: [[Double]],
                          nowMilliseconds: Int64,
                          fit: ([Epoch], Int) -> FitResult,
                          resetAction: (Int) -> FitResult) throws -> Transition {
        guard (0...5).contains(control) else { throw InputError.control }
        guard activeActionCount >= 0, nowMilliseconds >= 0,
              scoringHistory.allSatisfy(\.isFinite),
              Self.validMatrix(primary), Self.validMatrix(secondary) else { throw InputError.invalidInput }
        // Monotonic clock enforcement and finite matrix validation are our own
        // safety policy; vendor body does not provide these checks.
        if let previousClock, nowMilliseconds < previousClock { throw InputError.clockRegression }
        let nonempty = primary.contains { !$0.isEmpty }
        if control == 1 && nonempty && samples.addingReportingOverflow(configuration.stepSamples).overflow {
            throw InputError.sampleOverflow
        }
        previousClock = nowMilliseconds
        switch control {
        case 0:
            active = false
            return Transition()
        case 2:
            if epochs.count < configuration.minimumEpochs {
                // Vendor insufficient-accept path unlocks, but does not clear
                // active or invalidate timer. Do not silently repair it here.
                return Transition(event: 7, completed: true, unlockSettings: true)
            }
            let outcome = fit(epochs, action)
            active = false
            timerOriginMilliseconds = nil
            return Transition(event: 4, completed: true, unlockSettings: true,
                              fitResult: outcome, clearErrors: true, updateActions: true,
                              updateTrainingCount: true)
        case 3, 5:
            active = false
            timerOriginMilliseconds = nil
            return Transition(event: control == 3 ? 6 : 7, completed: true, unlockSettings: true)
        case 4:
            let outcome = resetAction(action)
            active = false
            let buildFailed: Bool
            if case .buildFailed = outcome { buildFailed = true } else { buildFailed = false }
            return Transition(event: 5, completed: true, fitResult: outcome,
                              clearErrors: buildFailed, updateActions: true,
                              thresholdAndScore: action == 1 ? nil : (Self.threshold(activeActionCount), 0))
        default:
            var result = Transition(lockSettings: true)
            if nonempty { samples += configuration.stepSamples }
            active = true
            if !startedEvent {
                startedEvent = true
                result.event = 1
                result.incrementTrainingAttempts = true
            }
            let elapsed: Int64
            if let origin = timerOriginMilliseconds { elapsed = (nowMilliseconds - origin) / 1000 }
            else { timerOriginMilliseconds = nowMilliseconds; elapsed = 0 }
            let sampleSeconds = Double(samples) / Double(configuration.samplingRate)
            let duration = Double(configuration.trainingSeconds)
            let wallCap = Double(configuration.trainingSeconds + Float(1.5))
            if sampleSeconds > Double(configuration.startAfterSeconds), sampleSeconds <= duration,
               Double(elapsed) < wallCap {
                if valid && nonempty {
                    if epochs.count >= configuration.maximumEpochs {
                        epochs.removeFirst(); result.droppedOldest = true
                    }
                    epochs.append(Epoch(primary: primary, secondary: secondary))
                    result.appended = true
                }
                return result
            }
            if sampleSeconds <= duration && Double(elapsed) < wallCap { return result }
            if action != 1 && actionPreviouslyTrained {
                let score = scoringHistory.isEmpty ? 0 : Double(scoringHistory.filter { $0 > 0 }.count) / Double(scoringHistory.count)
                result.thresholdAndScore = (Self.threshold(activeActionCount), score)
            }
            let enough = epochs.count >= configuration.minimumEpochs
            if !completionEvent {
                completionEvent = true
                result.event = enough ? 2 : 3
            }
            result.completed = !enough
            result.unlockSettings = !enough
            result.unlockTrainingControlOnly = enough
            return result
        }
    }

    /// Separate resetTrainingState boundary: clears flags, timer, counters and
    /// buffers. runTraining accept/reject does not itself perform this reset.
    mutating func resetState() {
        epochs.removeAll(); active = false; samples = 0
        startedEvent = false; completionEvent = false
        timerOriginMilliseconds = nil; previousClock = nil
    }
    static func threshold(_ count: Int) -> Double {
        guard count > 0 else { return 0 }
        let baseline = 1 / (Double(count) + 1)
        return baseline.addingProduct(0.5, 1 - baseline)
    }
    private static func validMatrix(_ value: [[Double]]) -> Bool {
        guard let width = value.first?.count else { return true }
        return value.allSatisfy { $0.count == width && $0.allSatisfy(\.isFinite) }
    }
}

/// onTrainingAccepted's build/save failure ordering. Operations are required;
/// neither event notification nor completing this function fabricates a model.
enum ReferenceTrainingPersistence {
    static func accept(build: () -> Bool, clearClassifier: () -> Void,
                       save: () -> Bool, clearErrors: () -> Void,
                       updateTrainingCount: () -> Void, updateActions: () -> Void,
                       updateBrainMapIfEligible: () -> Void,
                       unlockSettings: () -> Void) -> ReferenceNeutralTraining.FitResult {
        let outcome: ReferenceNeutralTraining.FitResult
        if build() { outcome = save() ? .saved : .saveFailed }
        else { clearClassifier(); outcome = .buildFailed(emptyBankSaved: save()) }
        clearErrors(); updateTrainingCount(); updateActions()
        // Eligibility and coordinate algorithms are explicit caller obligations.
        updateBrainMapIfEligible(); unlockSettings()
        return outcome
    }
}

/// buildClassifier's Matrix::combine method1 joins epoch columns in input order.
/// Matrices must have equal row counts; secondary timestamp matrices are combined
/// independently, rather than assumed to have the primary feature dimension.
enum ReferenceTrainingEpochAssembly {
    enum InputError: Error { case shape, capacity, nonFinite }
    static func combineColumns(_ matrices: [[[Double]]], maximumCells: Int) throws -> [[Double]] {
        guard maximumCells > 0 else { throw InputError.capacity }
        guard let first = matrices.first else { return [] }
        let rows = first.count
        var columns = 0
        for matrix in matrices {
            guard matrix.count == rows else { throw InputError.shape }
            let width = matrix.first?.count ?? 0
            guard matrix.allSatisfy({ $0.count == width }) else { throw InputError.shape }
            guard matrix.allSatisfy({ $0.allSatisfy(\.isFinite) }) else { throw InputError.nonFinite }
            let total = columns.addingReportingOverflow(width)
            guard !total.overflow else { throw InputError.capacity }
            columns = total.partialValue
        }
        let cells = rows.multipliedReportingOverflow(by: columns)
        guard !cells.overflow, cells.partialValue <= maximumCells else { throw InputError.capacity }
        return (0..<rows).map { row in matrices.flatMap { $0[row] } }
    }
}
