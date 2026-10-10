import XCTest
@testable import EEGCore

final class ReferenceRawTrainingWorkflowTests: XCTestCase {
    typealias W = ReferenceRawTrainingWorkflow
    enum Injected: Error { case beforeCommit }
    private func recipe(setting: Int = 3, step: Double = 1) -> ReferenceRawMentalWorkflow.Recipe {
        .init(sampleRate: 64, selectedChannelCount: 3, windowSeconds: 1, stepSeconds: step,
              maximumBufferedSamples: 128, maximumSamplesPerBlock: 64,
              bands: [.init(lowerHz: 2, upperHz: 10), .init(lowerHz: 10, upperHz: 20)],
              features: [.power(.init(row: 0, band: 0)), .power(.init(row: 1, band: 1))],
              backgroundEnabled: false, actions: [2], activationSetting: setting)
    }
    private func trial(action: Int32, count: Int = 40, amplitudeOffset: Double = 0) -> W.Trial {
        let blocks: [[[Double]]] = (0..<count).map { epoch in
            (0..<3).map { row in
                (0..<64).map { sample in
                    let t = Double(sample + epoch * 64) / 64
                    let amplitude = (action == 1 ? 2.0 : 3.0) + amplitudeOffset + 0.9 * sin(Double(epoch * (row + 1)) * 0.73)
                    let phase = Double(row) * 1.8 + Double(epoch) * 0.17
                    return amplitude * (sin(2 * .pi * (7 + Double(row)) * t + phase)
                        + 0.6 * cos(2 * .pi * (13 + Double(row)) * t + phase))
                        + 0.18 * sin(Double(sample * 17 + epoch * 11 + row * 23))
                }
            }
        }
        return .init(action: action, blocks: blocks, qualities: Array(repeating: 100, count: count),
                     timestamps: (0..<count).map { Double(100 + $0) })
    }
    private func prepared(trials: [W.Trial]? = nil, resumedRecord: W.Local.Record? = nil, rawRecipe: ReferenceRawMentalWorkflow.Recipe? = nil, timing: W.Timing? = nil) throws -> W.Prepared {
        try W.prepare(trials: trials ?? [trial(action: 1), trial(action: 2)], recipe: rawRecipe ?? recipe(),
            limits: .init(maximumCells: 1000, maximumEpochs: 100, maximumClasses: 4,
                maximumDistributionsPerClass: 8, storedMaximumEpochs: 100,
                storedMaximumDistributions: 4, maximumCanonicalDiagonalAdditions: 8),
            cacheLimit: 4, featureChannelMetadata: [[0, 0], [1, 1]],
            metadata: ["uuid": .string("raw-trial"), "name": .string("Authored raw fit"),
                "ownerId": .string("independent-tests"), "deleted": .bool(false), "loaded": .bool(true)],
            provenance: "authored-waveforms-not-participant-data", algorithmVersion: "reference-raw-v1", maximumBankBytes: 100_000, resumedRecord: resumedRecord, timing: timing)
    }
    private func url() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent("raw.sqlite")
    }
    func testRawTrainingFitDurableRestartAndSameReplay() throws {
        let prepared = try prepared()
        XCTAssertEqual(prepared.attempts.map { $0.collected.filter { $0.features?.clean == true }.count }, [40, 40])
        XCTAssertEqual(prepared.attempts[0].acceptance.build.route, .untrainedClass)
        XCTAssertEqual(prepared.attempts[1].acceptance.build.route, .fitted, prepared.attempts[1].acceptance.build.failureDescription ?? "no failure detail")
        XCTAssertTrue(prepared.attempts[1].deferredLifecycle.contains("brainMapEligibilityAndUpdateNotImplemented"))
        let profile = try XCTUnwrap(prepared.classifier)
        let settings = W.Local.Settings(classPriors: [1, 1], neutralScale: 1)
        var before = try ReferenceRawMentalWorkflow(recipe: recipe(), runtime:
            ReferenceRuntimeProfile.runtime(profile, classPriors: settings.classPriors, neutralScale: settings.neutralScale))
        let location = try url(), key = Data(repeating: 21, count: 32)
        let store = try W.Local(url: location, key: key)
        XCTAssertEqual(try W.save(prepared, id: "raw-trial", store: store, settings: settings, expectedRevision: 0), 1)
        try store.close()
        let reopened = try W.Local(url: location, key: key)
        let record = try XCTUnwrap(reopened.load(id: "raw-trial"))
        var after = try W.reopenWorkflow(record: record, recipe: recipe(), algorithmVersion: "reference-raw-v1")
        for block in trial(action: 2, count: 8).blocks {
            let a = try before.process(selectedChannelSamples: block, overallContactQuality: 100)
            let b = try after.process(selectedChannelSamples: block, overallContactQuality: 100)
            XCTAssertEqual(a.status, .inferred)
            XCTAssertEqual(a.features, b.features)
            XCTAssertEqual(a.classification?.posterior, b.classification?.posterior)
            XCTAssertEqual(a.command, b.command)
        }
        let updated = try self.prepared(trials: [trial(action: 2, amplitudeOffset: 2)], resumedRecord: record)
        XCTAssertEqual(updated.attempts.last?.acceptance.build.route, .fitted)
        XCTAssertNotEqual(updated.classifier, record.classifier)
        XCTAssertEqual(try W.save(updated, id: "raw-trial", store: reopened, settings: settings, expectedRevision: 1), 2)
        let revised = try XCTUnwrap(reopened.load(id: "raw-trial"))
        XCTAssertEqual(revised.revision, 2)
        // Inspect owned bank to prove the neutral class survived restart/retrain.
        let bounds = ReferenceClassifierRebuild.TrainingLimits(maximumCells: 1000, maximumEpochs: 100,
            maximumClasses: 4, maximumDistributionsPerClass: 8, storedMaximumEpochs: 100,
            storedMaximumDistributions: 4, maximumCanonicalDiagonalAdditions: 8)
        let oldBank = try W.reloadBank(record: record, recipe: recipe(), limits: bounds, maximumBytes: 100_000)
        let newBank = try W.reloadBank(record: revised, recipe: recipe(), limits: bounds, maximumBytes: 100_000)
        XCTAssertEqual(oldBank.gaussian[1], newBank.gaussian[1])
        XCTAssertEqual(oldBank.featureRows[1], newBank.featureRows[1])
        XCTAssertEqual(newBank.featureRows[2]?.count, 80)
        var oldInference = try W.reopenWorkflow(record: record, recipe: recipe(), algorithmVersion: "reference-raw-v1")
        var newInference = try W.reopenWorkflow(record: revised, recipe: recipe(), algorithmVersion: "reference-raw-v1")
        let probe = trial(action: 2, count: 1, amplitudeOffset: 1).blocks[0]
        let oldPrediction = try oldInference.process(selectedChannelSamples: probe, overallContactQuality: 100)
        let newPrediction = try newInference.process(selectedChannelSamples: probe, overallContactQuality: 100)
        XCTAssertNotEqual(oldPrediction.classification?.classDensity, newPrediction.classification?.classDensity)
        XCTAssertThrowsError(try W.reopenWorkflow(record: record, recipe: recipe(setting: 4), algorithmVersion: "reference-raw-v1"))
        XCTAssertThrowsError(try W.reopenWorkflow(record: record, recipe: recipe(), algorithmVersion: "other"))
    }
    func testPrecommitFailureAndUntrainedFitCannotClaimDurability() throws {
        let store = try W.Local(url: url(), key: Data(repeating: 22, count: 32))
        let settings = W.Local.Settings(classPriors: [1, 1], neutralScale: 1)
        let ready = try prepared()
        XCTAssertNotNil(ready.classifier, ready.attempts.last?.acceptance.build.failureDescription ?? "no failure detail")
        XCTAssertThrowsError(try W.save(ready, id: "raw-trial", store: store, settings: settings, expectedRevision: 0) {
            if case .beforeCommit = $0 { throw Injected.beforeCommit }
        }) { XCTAssertTrue($0 is Injected) }
        XCTAssertNil(try store.load(id: "raw-trial"))
        let rejected = try prepared(trials: [trial(action: 1, count: 4), trial(action: 2, count: 4)])
        XCTAssertEqual(rejected.attempts.last?.acceptance.build.route, .fitRejected)
        XCTAssertNil(rejected.classifier)
        XCTAssertThrowsError(try W.save(rejected, id: "raw-trial", store: store, settings: settings, expectedRevision: 0))
        XCTAssertNil(try store.load(id: "raw-trial"))
    }
    func testMalformedOwnedBankAndCollectionBoundsReject() throws {
        typealias V = ReferenceProfileCodec.Value
        let value = try prepared()
        let store = try W.Local(url: url(), key: Data(repeating: 23, count: 32))
        _ = try W.save(value, id: "raw-trial", store: store,
                       settings: .init(classPriors: [1, 1], neutralScale: 1), expectedRevision: 0)
        let record = try XCTUnwrap(store.load(id: "raw-trial"))
        let limits = ReferenceClassifierRebuild.TrainingLimits(maximumCells: 1000, maximumEpochs: 100,
            maximumClasses: 4, maximumDistributionsPerClass: 8, storedMaximumEpochs: 100,
            storedMaximumDistributions: 4, maximumCanonicalDiagonalAdditions: 8)
        func changed(_ edit: (inout [String: V]) -> Void) throws -> W.Local.Record {
            var metadata = record.metadata
            guard case var .object(state)? = metadata["independentRawTraining"] else { throw W.Failure.invalidInput }
            edit(&state)
            metadata["independentRawTraining"] = .object(state)
            return .init(metadata: metadata, classifier: record.classifier, settings: record.settings, revision: record.revision)
        }
        func changedFirstBankEntry(_ edit: (inout [String: V]) -> Void) throws -> W.Local.Record {
            try changed { state in
                guard case var .object(bank)? = state["trainingBank"],
                      case var .array(entries)? = bank["entries"],
                      case var .object(entry) = entries[0] else { XCTFail("Missing owned bank"); return }
                edit(&entry); entries[0] = .object(entry); bank["entries"] = .array(entries)
                state["trainingBank"] = .object(bank)
            }
        }
        for malformed in [try changedFirstBankEntry { $0["id"] = .number(99) },
                          try changedFirstBankEntry { $0["featureRows"] = .array([.array([.number(1)])]) }] {
            XCTAssertThrowsError(try W.reloadBank(record: malformed, recipe: recipe(), limits: limits, maximumBytes: 100_000))
        }
        XCTAssertThrowsError(try W.reloadBank(record: record, recipe: recipe(), limits: limits, maximumBytes: 32))
        let small = ReferenceClassifierRebuild.TrainingLimits(maximumCells: 1000, maximumEpochs: 1,
            maximumClasses: 4, maximumDistributionsPerClass: 8, storedMaximumEpochs: 100,
            storedMaximumDistributions: 4, maximumCanonicalDiagonalAdditions: 8)
        XCTAssertThrowsError(try W.reloadBank(record: record, recipe: recipe(), limits: small, maximumBytes: 100_000))
        let changedMetadata = try changed { $0["featureChannelMetadata"] = .array([]) }
        XCTAssertThrowsError(try prepared(trials: [trial(action: 2)], resumedRecord: changedMetadata))
        let normal = trial(action: 1, count: 2)
        let reversed = W.Trial(action: 1, blocks: normal.blocks, qualities: normal.qualities, timestamps: [101, 100])
        XCTAssertThrowsError(try prepared(trials: [reversed]))
        XCTAssertThrowsError(try prepared(trials: [trial(action: 1, count: 101)]))
    }

    func testTimedLifecycleUsesSeparateClockDelayMinimumAndDuration() throws {
        let rawRecipe = recipe(step: 0.25)
        func timedTrial(_ action: Int32) -> W.Trial {
            let input = trial(action: action, count: 10).blocks
            let rows = (0..<3).map { channel in input.flatMap { $0[channel] } }
            let blocks = stride(from: 0, to: 640, by: 16).map { start in rows.map { Array($0[start..<(start + 16)]) } }
            return .init(action: action, blocks: blocks, qualities: Array(repeating: 100, count: 40),
                         timestamps: (0..<40).map { Double(5000 + $0) })
        }
        let trials = [timedTrial(1), timedTrial(2)]
        // Explicit recovered duration/delay/min/max, compatible caller step.
        let config = ReferenceTrainingLifecycle.Configuration(samplingRate: 64, stepSamples: 16,
            startAfterSeconds: 1, trainingSeconds: 8, minimumEpochs: 12, maximumEpochs: 100)
        let clocks = (0..<40).map { Int64($0 * 250) }
        let timing = W.Timing(configuration: config, collectionMilliseconds: [clocks, clocks],
                              acceptanceMilliseconds: [10_000, 10_000], scoringHistories: [[], []])
        let output = try prepared(trials: trials, rawRecipe: rawRecipe, timing: timing)
        XCTAssertNotNil(output.classifier, output.attempts.last?.acceptance.build.failureDescription ?? "no description")
        for attempt in output.attempts {
            XCTAssertEqual(attempt.trainingTransitions.filter(\.appended).count, 28)
            XCTAssertFalse(attempt.trainingTransitions[6].appended)
            XCTAssertTrue(attempt.trainingTransitions[7].appended)
            XCTAssertEqual(attempt.trainingTransitions[35].event, 2)
            XCTAssertEqual(attempt.trainingTransitions.last?.event, 4)
        }
        let fastWall = (0..<40).map { Int64($0 * 1000) }
        let expired = W.Timing(configuration: config, collectionMilliseconds: [fastWall, fastWall],
                               acceptanceMilliseconds: [40_000, 40_000], scoringHistories: [[], []])
        XCTAssertThrowsError(try prepared(trials: trials, rawRecipe: rawRecipe, timing: expired)) {
            guard case W.Failure.lifecycleRejected(event: 7, collected: let count) = $0 else {
                return XCTFail("Expected insufficient lifecycle collection, got \($0)")
            }
            XCTAssertLessThan(count, 12)
        }
    }

}
