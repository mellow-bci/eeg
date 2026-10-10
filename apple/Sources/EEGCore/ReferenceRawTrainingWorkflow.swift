import Foundation

/// Independent comparison harness. Owned SQLite records atomically preserve
/// recipe, classifier and collected training bank; not vendor transaction parity.
enum ReferenceRawTrainingWorkflow {
    typealias Raw = ReferenceRawMentalWorkflow
    typealias Local = ReferenceLocalProfileStore
    enum Failure: Error { case invalidInput, noUsableEpochs, noClassifier, incompatibleProvenance
        case lifecycleRejected(event: Int?, collected: Int) }
    struct Trial {
        let action: Int32
        let blocks: [[[Double]]]
        /// One supplied quality/timestamp per invocation, including empty ticks.
        let qualities: [Double]
        let timestamps: [Double]
    }
    struct Timing {
        let configuration: ReferenceTrainingLifecycle.Configuration
        /// Separate monotonic clock domain, never derived from stored timestamps.
        let collectionMilliseconds: [[Int64]]
        let acceptanceMilliseconds: [Int64]
        let scoringHistories: [[Double]]
    }
    struct Attempt {
        let action: Int32
        let collected: [Raw.Frame]
        let acceptance: ReferenceClassifierRebuild.Acceptance
        /// Requested vendor lifecycle side effects are observable, not claimed
        /// implemented by this harness. In particular no brain map is fabricated.
        let deferredLifecycle: [String]
        let trainingTransitions: [ReferenceTrainingLifecycle.Transition]
    }
    struct Prepared {
        let attempts: [Attempt]
        let classifier: ReferenceProfileCodec.Classifier?
        let metadata: [String: ReferenceProfileCodec.Value]
    }

    static func prepare(trials: [Trial], recipe: Raw.Recipe,
                        limits: ReferenceClassifierRebuild.TrainingLimits,
                        cacheLimit: Int, featureChannelMetadata: [[Double]],
                        metadata: [String: ReferenceProfileCodec.Value],
                        provenance: String, algorithmVersion: String, maximumBankBytes: Int,
                        resumedRecord: Local.Record? = nil, timing: Timing? = nil) throws -> Prepared {
        guard !trials.isEmpty, !recipe.features.isEmpty, !provenance.isEmpty, !algorithmVersion.isEmpty,
              limits.maximumEpochs > 0, limits.maximumCells > 0,
              trials.count <= limits.maximumCells,
              recipe.actions.allSatisfy({ Int32(exactly: $0) != nil }) else { throw Failure.invalidInput }
        if let timing {
            let stream = try ReferenceEpochStream(sampleRate: recipe.sampleRate, windowSeconds: recipe.windowSeconds,
                stepSeconds: recipe.stepSeconds, maximumBufferedSamples: recipe.maximumBufferedSamples)
            guard timing.collectionMilliseconds.count == trials.count,
                  timing.acceptanceMilliseconds.count == trials.count,
                  timing.scoringHistories.count == trials.count,
                  timing.configuration.samplingRate == UInt64(recipe.sampleRate),
                  timing.configuration.stepSamples == UInt64(stream.stepSamples),
                  timing.configuration.maximumEpochs <= limits.maximumEpochs,
                  timing.configuration.maximumEpochs <= limits.maximumCells / recipe.features.count else { throw Failure.invalidInput }
        }
        let actions = [Int32(1)] + recipe.actions.map { Int32($0) }
        var bank = ReferenceTrainingDatabase.Store()
        if let resumedRecord {
            _ = try reopenWorkflow(record: resumedRecord, recipe: recipe, algorithmVersion: algorithmVersion)
            guard case let .object(saved)? = resumedRecord.metadata["independentRawTraining"],
                  saved["featureChannelMetadata"] == matrixValue(featureChannelMetadata) else {
                throw Failure.incompatibleProvenance
            }
            bank = try reloadBank(record: resumedRecord, recipe: recipe, limits: limits, maximumBytes: maximumBankBytes)
        }
        var cache = try ReferenceClassifierCache<ReferenceClassifierRebuild.Signature>(storageLimit: cacheLimit)
        var signature: ReferenceClassifierRebuild.Signature?
        var attempts: [Attempt] = []
        var classifierProperty: ReferenceClassifierRebuild.Signature?
        for (trialIndex, trial) in trials.enumerated() {
            guard actions.contains(trial.action), trial.blocks.count == trial.qualities.count,
                  trial.blocks.count == trial.timestamps.count,
                  trial.blocks.count <= limits.maximumCells else { throw Failure.invalidInput }
            // Separate labeled trials cannot share filter/overlap/background state.
            // This independent experiment boundary is not an inferred manager reset.
            var raw = try Raw(recipe: recipe, runtime: nil)
            var lifecycle = try timing.map { try ReferenceTrainingLifecycle(configuration: $0.configuration) }
            if let timing { guard timing.collectionMilliseconds[trialIndex].count == trial.blocks.count else { throw Failure.invalidInput } }
            var transitions: [ReferenceTrainingLifecycle.Transition] = []
            var frames: [Raw.Frame] = [], features: [[[Double]]] = [], times: [[[Double]]] = []
            for index in trial.blocks.indices {
                guard trial.timestamps[index].isFinite, trial.timestamps[index] >= 0,
                      trial.timestamps[index] <= Double(UInt32.max),
                      index == 0 || trial.timestamps[index] >= trial.timestamps[index - 1] else { throw Failure.invalidInput }
                let frame = try raw.process(selectedChannelSamples: trial.blocks[index],
                                            overallContactQuality: trial.qualities[index])
                frames.append(frame)
                if let timing {
                    let value = frame.features
                    let transition = try lifecycle!.advance(control: 1, action: Int(trial.action),
                        activeActionCount: recipe.actions.count, actionPreviouslyTrained: bank.gaussian[trial.action] != nil,
                        scoringHistory: timing.scoringHistories[trialIndex], valid: value?.clean == true,
                        primary: value?.processed.map { [$0] } ?? [], secondary: [[trial.timestamps[index]]],
                        nowMilliseconds: timing.collectionMilliseconds[trialIndex][index],
                        fit: { _, _ in .buildFailed(emptyBankSaved: false) },
                        resetAction: { _ in .buildFailed(emptyBankSaved: false) })
                    transitions.append(transition)
                } else if let value = frame.features, value.clean {
                    guard features.count < limits.maximumEpochs,
                          value.processed.count > 0,
                          features.count < limits.maximumCells / value.processed.count else { throw Failure.invalidInput }
                    features.append(value.processed.map { [$0] })
                    times.append([[trial.timestamps[index]]])
                }
            }
            if let lifecycle {
                features = lifecycle.epochs.map(\.primary)
                times = lifecycle.epochs.map(\.secondary)
            }
            if timing == nil { guard !features.isEmpty else { throw Failure.noUsableEpochs } }
            var events: [String] = []
            func accept(_ features: [[[Double]]], _ times: [[[Double]]]) throws -> ReferenceClassifierRebuild.Acceptance {
                try ReferenceClassifierRebuild.acceptTraining(actions: actions,
                trainingAction: trial.action, pendingFeatures: features, pendingTimestamps: times,
                featureChannelMetadata: featureChannelMetadata, limits: limits,
                store: &bank, cache: &cache, classifier: &signature,
                // This acknowledges only in-memory property assignment. Durable
                // persistence below is a separate throwing operation with receipt.
                saveClassifier: { value in classifierProperty = value; return true },
                clearErrors: { events.append("clearErrors") },
                updateTrainingCount: { events.append("updateTrainingCount") },
                updateActions: { events.append("updateActions") },
                updateBrainMapIfEligible: { events.append("brainMapEligibilityAndUpdateNotImplemented") },
                unlockSettings: { events.append("unlockSettings") })
            }
            let accepted: ReferenceClassifierRebuild.Acceptance
            if let timing {
                var acceptance: ReferenceClassifierRebuild.Acceptance?
                var fitError: Error?
                let transition = try lifecycle!.advance(control: 2, action: Int(trial.action),
                    activeActionCount: recipe.actions.count, actionPreviouslyTrained: bank.gaussian[trial.action] != nil,
                    scoringHistory: timing.scoringHistories[trialIndex], valid: false, primary: [], secondary: [],
                    nowMilliseconds: timing.acceptanceMilliseconds[trialIndex], fit: { epochs, _ in
                        do {
                            let result = try accept(epochs.map(\.primary), epochs.map(\.secondary))
                            acceptance = result; return result.outcome
                        } catch { fitError = error; return .buildFailed(emptyBankSaved: false) }
                    }, resetAction: { _ in .buildFailed(emptyBankSaved: false) })
                transitions.append(transition)
                if let fitError { throw fitError }
                guard let acceptance else { throw Failure.lifecycleRejected(event: transition.event, collected: features.count) }
                accepted = acceptance
            } else { accepted = try accept(features, times) }
            attempts.append(.init(action: trial.action, collected: frames,
                                  acceptance: accepted, deferredLifecycle: events, trainingTransitions: transitions))
        }
        let profile = try classifierProperty.map {
            try ReferenceRuntimeProfile.classifier($0, numOfValidFeatures: $0.pca.basis[0].count, useCount: 0)
        }
        var metadata = metadata
        metadata["independentRawTraining"] = .object([
            "schemaVersion": .number(1), "algorithmVersion": .string(algorithmVersion),
            "collectionPath": .string(timing == nil ? "independent-reviewed-epochs" : "reference-timed-lifecycle"),
            "trainingTiming": timing.map(timingContract) ?? .null,
            "provenance": .string(provenance), "recipe": contract(recipe),
            "trainingBankDurable": .bool(true),
            "featureChannelMetadata": matrixValue(featureChannelMetadata),
            "trainingBank": try encodeBank(bank, maximumBytes: maximumBankBytes)])
        return .init(attempts: attempts, classifier: profile, metadata: metadata)
    }

    /// Failed fits cannot be reported as durable success. Store owns transaction
    /// rollback and distinguishes committed-but-unacknowledged outcomes.
    static func save(_ prepared: Prepared, id: String, store: Local,
                     settings: Local.Settings, expectedRevision: Int64,
                     fault: ((Local.WriteStage) throws -> Void)? = nil) throws -> Int64 {
        guard let classifier = prepared.classifier else { throw Failure.noClassifier }
        return try store.save(id: id, metadata: prepared.metadata, classifier: classifier,
                              settings: settings, expectedRevision: expectedRevision, fault: fault)
    }

    static func reopenWorkflow(record: Local.Record, recipe: Raw.Recipe,
                               algorithmVersion: String) throws -> Raw {
        guard case let .object(value)? = record.metadata["independentRawTraining"],
              value["schemaVersion"] == .number(1),
              value["algorithmVersion"] == .string(algorithmVersion),
              value["recipe"] == contract(recipe),
              value["trainingBankDurable"] == .bool(true) else { throw Failure.incompatibleProvenance }
        return try Raw(recipe: recipe, runtime: record.runtime)
    }


    private static func timingContract(_ timing: Timing) -> ReferenceProfileCodec.Value {
        let c = timing.configuration
        return .object(["samplingRate": .number(Double(c.samplingRate)),
            "stepSamples": .number(Double(c.stepSamples)), "startAfterSeconds": .number(Double(c.startAfterSeconds)),
            "trainingSeconds": .number(Double(c.trainingSeconds)), "minimumEpochs": .number(Double(c.minimumEpochs)),
            "maximumEpochs": .number(Double(c.maximumEpochs)),
            "collectionMilliseconds": .array(timing.collectionMilliseconds.map { .array($0.map { .number(Double($0)) }) }),
            "acceptanceMilliseconds": .array(timing.acceptanceMilliseconds.map { .number(Double($0)) }),
            "scoringHistories": matrixValue(timing.scoringHistories)])
    }

    private struct BankEntry: Codable {
        let id: Int32
        let gaussian: ReferenceTrainingBank.ClassEntry
        let featureRows: [[Double]]
        let timestampRows: [[Double]]
    }
    private struct BankSnapshot: Codable { let entries: [BankEntry] }
    private static func matrixValue(_ rows: [[Double]]) -> ReferenceProfileCodec.Value {
        .array(rows.map { .array($0.map(ReferenceProfileCodec.Value.number)) })
    }
    private static func encodeBank(_ bank: ReferenceTrainingDatabase.Store, maximumBytes: Int) throws -> ReferenceProfileCodec.Value {
        let entries = bank.gaussian.keys.sorted().map { id in
            BankEntry(id: id, gaussian: bank.gaussian[id]!, featureRows: bank.featureRows[id] ?? [],
                      timestampRows: bank.timestampRows[id] ?? [])
        }
        let bytes = try JSONEncoder().encode(BankSnapshot(entries: entries))
        return .object(try ReferenceProfileCodec.decodeJSONObject(bytes, maximumBytes: maximumBytes, maximumNesting: 32))
    }
    /// Owned-format decode with caller-supplied resource bounds. Exposes actual
    /// bank values for audit; no vendor encrypted-file or trained asset import.
    static func reloadBank(record: Local.Record, recipe: Raw.Recipe,
                           limits: ReferenceClassifierRebuild.TrainingLimits,
                           maximumBytes: Int) throws -> ReferenceTrainingDatabase.Store {
        guard case let .object(metadata)? = record.metadata["independentRawTraining"],
              case let .object(object)? = metadata["trainingBank"],
              metadata["schemaVersion"] == .number(1), metadata["trainingBankDurable"] == .bool(true),
              metadata["recipe"] == contract(recipe), limits.maximumEpochs > 0,
              limits.maximumCells > 0, limits.maximumClasses > 0,
              limits.maximumDistributionsPerClass > 0 else { throw Failure.incompatibleProvenance }
        let bytes = try ReferenceProfileCodec.encodeJSONObject(object, maximumBytes: maximumBytes, maximumNesting: 32)
        let snapshot = try JSONDecoder().decode(BankSnapshot.self, from: bytes)
        let actions = Set([Int32(1)] + recipe.actions.compactMap { Int32(exactly: $0) })
        guard snapshot.entries.count <= limits.maximumClasses,
              Set(snapshot.entries.map(\.id)).count == snapshot.entries.count else { throw Failure.invalidInput }
        var bank = ReferenceTrainingDatabase.Store()
        for entry in snapshot.entries {
            guard actions.contains(entry.id), entry.gaussian.classReferenceID == entry.id,
                  entry.gaussian.distributions.count <= limits.maximumDistributionsPerClass,
                  entry.featureRows.count <= limits.maximumEpochs,
                  entry.featureRows.count == entry.timestampRows.count else { throw Failure.invalidInput }
            for rows in [entry.featureRows, entry.timestampRows] {
                var cells = 0
                for row in rows {
                    guard row.count <= limits.maximumCells - cells, row.allSatisfy(\.isFinite) else { throw Failure.invalidInput }
                    cells += row.count
                }
            }
            guard entry.featureRows.allSatisfy({ $0.count == recipe.features.count }),
                  entry.timestampRows.allSatisfy({ $0.count == 1 && $0[0] >= 0 && $0[0] <= Double(UInt32.max) }) else { throw Failure.invalidInput }
            for distribution in entry.gaussian.distributions {
                guard distribution.mean.count == recipe.features.count else { throw Failure.invalidInput }
                _ = try ReferenceGaussianPooling.combine(distribution, nil, useFirstUpdateTime: false)
            }
            bank.gaussian[entry.id] = entry.gaussian
            bank.featureRows[entry.id] = entry.featureRows
            bank.timestampRows[entry.id] = entry.timestampRows
        }
        return bank
    }

    /// Versioned owned contract. Exact equality rejects changed restart settings.
    private static func contract(_ r: Raw.Recipe) -> ReferenceProfileCodec.Value {
        typealias V = ReferenceProfileCodec.Value
        func coordinate(_ c: ReferenceDeployedFeatures.Coordinate) -> V {
            .array([.number(Double(c.row)), .number(Double(c.band))])
        }
        let features: [V] = r.features.map {
            switch $0 {
            case .power(let c): return .array([.string("power"), coordinate(c)])
            case .ratio(let a, let b): return .array([.string("ratio"), coordinate(a), coordinate(b)])
            }
        }
        return .object(["sampleRate": .number(Double(r.sampleRate)),
            "selectedChannels": .number(Double(r.selectedChannelCount)),
            "windowSeconds": .number(r.windowSeconds), "stepSeconds": .number(r.stepSeconds),
            "maximumBufferedSamples": .number(Double(r.maximumBufferedSamples)),
            "maximumSamplesPerBlock": .number(Double(r.maximumSamplesPerBlock)),
            "bands": .array(r.bands.map { .array([.number($0.lowerHz), .number($0.upperHz)]) }),
            "features": .array(features), "backgroundEnabled": .bool(r.backgroundEnabled),
            "actions": .array(r.actions.map { .number(Double($0)) }),
            "activationSetting": .number(Double(r.activationSetting))])
    }
}
