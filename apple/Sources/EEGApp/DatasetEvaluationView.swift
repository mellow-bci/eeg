import SwiftUI
import UniformTypeIdentifiers
import EEGCore

struct DatasetEvaluationView: View {
    let profile: EEGMentalProfile
    let preparedManifest: Data?
    @State private var generation = 0
    @EnvironmentObject private var model: AcquisitionModel
    @State private var controlsOnly = false
    @State private var minimumWindows = "10"
    @State private var associationEnabled = false
    @State private var associationPercent = "80"
    @State private var resamplingEnabled = false
    @State private var resamplingIterations = "10000"
    @State private var resamplingSeed = "0"
    @State private var resamplingPercent = "95"
    @State private var importing = false
    @State private var running = false
    @State private var evaluationWorker: Task<Result<EEGEvaluationArtifact, Error>, Never>?
    @State private var artifact: EEGEvaluationArtifact?
    @State private var exporting = false
    @State private var exportData = Data()
    @State private var exportMessage: String?
    private var report: EEGLabeledEvaluation? { artifact?.report }
    @State private var failure: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text("Evaluate labeled sessions").font(.headline)
            Toggle("Controls-only evaluation", isOn: $controlsOnly).disabled(running)
                .onChange(of: controlsOnly) { _, _ in artifact = nil; failure = nil; exportMessage = nil }
            LabeledContent("Minimum windows per class") {
                TextField("Minimum windows per class", text: $minimumWindows).labelsHidden().accessibilityLabel("Minimum windows per class")
            }.disabled(running)
            Text("A data-count requirement, not proof of adequate physiological evidence. Rejected windows count toward it.").font(.caption)
            DisclosureGroup("Conditional trial-schedule comparison") {
                Toggle("Include trial-schedule comparison", isOn: $associationEnabled)
                if associationEnabled {
                    LabeledContent("Minimum eligible exposure (%)") {
                        TextField("Minimum eligible exposure", text: $associationPercent).labelsHidden()
                            .accessibilityLabel("Minimum eligible exposure percentage per trial")
                    }
                    Text("Requires every trial in a complete reviewed native plan. Freeze this threshold before viewing results. Schedule association does not establish neural origin or valid randomization.").font(.caption)
                }
            }.disabled(running)
            DisclosureGroup("Exploratory session resampling") {
                Toggle("Include session resampling range", isOn: $resamplingEnabled)
                if resamplingEnabled {
                    LabeledContent("Resamples") {
                        TextField("Resamples", text: $resamplingIterations).labelsHidden().accessibilityLabel("Resamples")
                    }
                    LabeledContent("Reproducible seed") {
                        TextField("Reproducible seed", text: $resamplingSeed).labelsHidden().accessibilityLabel("Reproducible seed")
                    }
                    LabeledContent("Central percentage") {
                        TextField("Central percentage", text: $resamplingPercent).labelsHidden().accessibilityLabel("Central percentage")
                    }
                    Text("Keeps each session intact. This range is not validated confidence coverage; few sessions or dependent acquisitions limit interpretation. It never enables control.").font(.caption)
                }
            }.disabled(running)
            Text(controlsOnly ? "Only neutral-labeled control conditions are accepted. Task recall cannot be measured from control trials." : "Full evaluation requires at least \(minimumWindows) windows per class.").font(.caption)
            Text("Choose a dataset manifest with evaluation sessions. Rejected windows remain in the denominator; labels are declarations, not independently verified mental states.").foregroundStyle(.secondary)
            Button("Evaluate prepared dataset", systemImage: "chart.bar") {
                if let data=preparedManifest { evaluate { data } }
            }.disabled(preparedManifest == nil || running || model.recording || model.ready)
            Button("Open dataset and evaluate", systemImage: "doc.badge.plus") { importing = true }
                .disabled(running || model.recording || model.ready)
            if running {
                ProgressView("Evaluating held-out recordings…")
                Button("Cancel evaluation") { evaluationWorker?.cancel() }
            }
            if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
            if let report {
                Button("Export evaluation JSON", systemImage: "square.and.arrow.up") {
                    guard let artifact else { return }
                    exportData = artifact.data; exporting = true
                }
                if let exportMessage { Text(exportMessage).font(.caption) }
                if let associations = artifact?.trialAssociation {
                    DisclosureGroup("Trial-schedule comparison results — conditional") {
                        ForEach(associations.keys.sorted(), id: \.self) { session in
                            let assessment = associations[session]!
                            Text("Session: " + session).font(.headline)
                            if let value = assessment.result {
                                LabeledContent("At least observed / permitted schedules",
                                    value: "\(value.association.atLeastObservedSchedules) / \(value.association.admissibleSchedules)")
                                LabeledContent("Minimum eligible exposure", value: percent(value.minimumEligibleFraction))
                                Text("Conditional association only; exchangeability unverified.").font(.caption)
                            } else {
                                Text("Unavailable: " + assessment.explanation)
                            }
                        }
                        Text("No automatic significance, physiological qualification or system-control decision.").font(.caption)
                    }
                }
                if let resampling = artifact?.sessionResampling {
                    DisclosureGroup("Session resampling results — exploratory") {
                        ForEach(resampling.keys.sorted(), id: \.self) { label in
                            let value = resampling[label]!
                            Text("\(label): \(value.sessionIDs.count) sessions · \(value.status.replacingOccurrences(of: "_", with: " "))")
                            if let low = value.lower, let high = value.upper {
                                Text("Central \(value.options.centralMass.formatted(.percent)) range: \(percent(low))–\(percent(high))")
                            }
                        }
                        Text("Not a validated confidence interval or qualification decision. Review missing exposure and session independence separately.").font(.caption)
                    }
                }
                if let audit = artifact?.trainingSourceAudit {
                    LabeledContent("Profile training sources present", value: "\(audit.matches.count) / \(profile.trainingSessions.count)")
                    if !audit.missingTrainingSessions.isEmpty {
                        Text("Missing original training sources: " + audit.missingTrainingSessions.joined(separator: ", ")).textSelection(.enabled)
                        Text("Historical excerpt reuse cannot be checked against these missing sources. Include the original recordings as training sources in this manifest; evaluation does not refit the profile.").font(.caption)
                    }
                    Text("Source coverage is a content check, not proof of independent sessions or mental-command accuracy.").font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("Scope", value: report.controlsOnly ? "Controls only" : "Full labeled evaluation")
                if !report.controlConditionsWithoutEligibleExposure.isEmpty {
                    Text("No eligible control exposure: " + report.controlConditionsWithoutEligibleExposure.map { $0.replacingOccurrences(of:"_",with:" ") }.joined(separator:", ")).font(.callout)
                }
                Text("Control coverage indicates presence only. Adequate duration and real artifact-response validation are still required.").font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Always-neutral baseline — window comparison") {
                    Text("Predicts neutral without using EEG, including windows rejected by the detector. Class imbalance can make this baseline look accurate; it cannot detect tasks.").font(.caption)
                    ForEach(report.alwaysNeutralMetrics.keys.sorted(), id: \.self) { label in
                        let baseline = report.alwaysNeutralMetrics[label]!
                        Text("\(label): detector recall \(percent(report.metrics[label]?.recall)) · baseline recall \(percent(baseline.recall))")
                    }
                    Text("For cued trials with available evidence, this baseline has zero task detections and zero neutral false-positive candidates. Missing cue evidence remains unavailable in the receipt.").font(.caption)
                    Text("Window comparisons are descriptive. Correlated windows are not independent trials; this does not establish significance or physiological validity.").font(.caption)
                }
                LabeledContent("Evaluation windows", value: String(report.predictions.count))
                confusionSummary(report.confusion)
                LabeledContent("Rejected", value: report.rejectionFraction.formatted(.percent.precision(.fractionLength(1))))
                ForEach(report.metrics.keys.sorted(), id: \.self) { label in
                    let metric = report.metrics[label]!
                    VStack(alignment: .leading) {
                        Text(label).font(.headline)
                        Text("TP \(metric.truePositive) · FP \(metric.falsePositive) · FN \(metric.falseNegative)").monospacedDigit()
                        Text("Precision: \(percent(metric.precision)) · Recall: \(percent(metric.recall))")
                        Text("Rejected: \(metric.rejectedWindows) / \(metric.actualWindows) · \(percent(metric.rejectionFraction))").monospacedDigit()
                    }.accessibilityElement(children: .combine)
                }
                DisclosureGroup("Cued trial observations") {
                    Text("One observation per trial. Missing cues are unavailable; trials with no usable exposure remain visible. Neutral observations are false positives.").font(.caption)
                    let trialMetrics = report.trialMetrics
                    ForEach(trialMetrics.keys.sorted(), id: \.self) { label in
                        trialSummary(label: label, metric: trialMetrics[label]!)
                    }
                }
                ForEach(report.conditions.keys.sorted(), id: \.self) { condition in
                    let exposure = report.conditions[condition]!
                    exposureSummary(condition: condition, exposure: exposure)
                }
                DisclosureGroup("Results by session") {
                    let metricsBySession = report.sessionMetrics
                    let trialsBySession = report.sessionTrialMetrics
                    Text("Compare individual sessions before interpreting pooled rates.").font(.caption)
                    ForEach(report.sessionConditions.keys.sorted(), id: \.self) { session in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(session).font(.headline).textSelection(.enabled)
                            let metrics = metricsBySession[session] ?? [:]
                            confusionSummary(report.sessionConfusion[session] ?? [:])
                            ForEach(metrics.keys.sorted(),id: \.self) { label in
                                let metric = metrics[label]!
                                Text("\(label): precision \(percent(metric.precision)) · recall \(percent(metric.recall)) · TP \(metric.truePositive) / FP \(metric.falsePositive) / FN \(metric.falseNegative) · rejected \(metric.rejectedWindows) / \(metric.actualWindows) (\(percent(metric.rejectionFraction)))").font(.caption).monospacedDigit()
                            }
                            let trialMetrics = trialsBySession[session] ?? [:]
                            ForEach(trialMetrics.keys.sorted(), id: \.self) { label in
                                trialSummary(label: label, metric: trialMetrics[label]!)
                            }
                            ForEach(report.sessionConditions[session]!.keys.sorted(), id: \.self) { condition in
                                exposureSummary(condition: condition, exposure: report.sessionConditions[session]![condition]!)
                            }
                        }
                    }
                }
                ForEach(Array(report.trials.enumerated()), id: \.offset) { _, trial in
                    VStack(alignment: .leading) {
                        Text("\(trial.sessionID) / \(trial.trialID)").font(.headline)
                        Text("Armed usable coverage: \(percent(trial.eligibleFraction))")
                        if trial.condition == "cued_task" {
                            Text("Target candidate within scored interval: \(trial.scoredTargetDetected.map { $0 ? "Observed" : "Not observed" } ?? "Unavailable — missing cue")")
                        } else if trial.condition == "cued_neutral" {
                            Text("Task candidate during neutral trial: \(trial.scoredNeutralFalsePositive.map { $0 ? "Observed (false positive)" : "Not observed" } ?? "Unavailable — missing cue")")
                        }
                        Text("Unobserved interval: \(trial.unobservedSeconds.formatted(.number.precision(.fractionLength(2)))) s")
                        Text("Cue-associated candidate latency: \(trial.firstCueAssociatedCandidateLatency.map { $0.formatted(.number.precision(.fractionLength(2))) + " s" } ?? "Unavailable")")
                    }.font(.caption).accessibilityElement(children: .combine)
                }
                Text("Latency is measured from recorded cue completion to candidate input availability, not mental onset or live-system response.").font(.caption).foregroundStyle(.secondary)
                Text("Experimental window and trial accounting. Not observed includes rejected or missing exposure; inspect coverage. Windows within trials are correlated. These values do not establish physiological accuracy, physiologically validated false-activation rates or safe system control. Poisson bounds assume a constant independent event rate; clustered events weaken that assumption. Carry-in activity makes rates unavailable.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .onDisappear { evaluationWorker?.cancel() }
        .onChange(of: minimumWindows) { _,_ in artifact=nil;failure=nil;exportMessage=nil }
        .onChange(of: associationEnabled) { _,_ in artifact=nil;failure=nil;exportMessage=nil }
        .onChange(of: associationPercent) { _,_ in artifact=nil;failure=nil;exportMessage=nil }
        .onChange(of: resamplingEnabled) { _,_ in artifact=nil;failure=nil;exportMessage=nil }
        .onChange(of: resamplingIterations) { _,_ in artifact=nil;failure=nil;exportMessage=nil }
        .onChange(of: resamplingSeed) { _,_ in artifact=nil;failure=nil;exportMessage=nil }
        .onChange(of: resamplingPercent) { _,_ in artifact=nil;failure=nil;exportMessage=nil }
        .onChange(of: preparedManifest) { _,_ in generation += 1;artifact=nil;failure=nil;exportMessage=nil }
        .eegJSONImporter(isPresented: $importing) { selection in
            switch selection {
            case .failure(let error): failure = error.localizedDescription
            case .success(let url): evaluate(url)
            }
        }
        .fileExporter(isPresented: $exporting, document: EvaluationDocument(data: exportData), contentType: .json, defaultFilename: "eeg-evaluation.json") { result in
            switch result {
            case .success: exportMessage = "Evaluation receipt exported. Keep the matching profile and original recordings for reproduction."
            case .failure(let error): failure = "Export failed: \(error.localizedDescription)"
            }
        }
    }
    private func confusionSummary(_ rows: [String: EEGLabeledEvaluation.ConfusionRow]) -> some View {
        ConfusionMatrixView(rows: rows)
    }
    private func trialSummary(label: String, metric: EEGLabeledEvaluation.TrialMetric) -> some View {
        VStack(alignment: .leading) {
            Text(label == "neutral" ? "Neutral trial false positives" : "\(label) trial target observations").font(.headline)
            Text("Observed: \(metric.observedTrials) / \(metric.scoredTrials) · \(percent(metric.observationFraction))").monospacedDigit()
            Text("Declared: \(metric.declaredTrials) · Missing cue: \(metric.unavailableTrials) · No eligible exposure: \(metric.trialsWithoutEligibleExposure)").monospacedDigit()
            Text("Armed usable coverage: \(percent(metric.eligibleFraction))")
        }.font(.caption).accessibilityElement(children: .combine)
    }
    private func exposureSummary(condition: String, exposure: EEGConditionExposure) -> some View {
                    VStack(alignment: .leading) {
                        Text(condition.replacingOccurrences(of: "_", with: " ")).font(.headline)
                        Text("Eligible: \(exposure.eligibleSeconds.formatted(.number.precision(.fractionLength(2)))) s · Rejected: \(exposure.rejectedSeconds.formatted(.number.precision(.fractionLength(2)))) s · Unarmed: \(exposure.unarmedSeconds.formatted(.number.precision(.fractionLength(2)))) s")
                        Text("Candidate episodes: \(exposure.episodeOnsets) · Carry-ins: \(exposure.carryInCandidates)")
                        Text("Empirical episodes/hour: \(exposure.episodeOnsetsPerHour.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "Unavailable")")
                        Text("One-sided 95% Poisson upper/hour: \(exposure.poissonUpper95PerHour.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "Unavailable")")
                    }.font(.caption).accessibilityElement(children: .combine)
    }
    private func percent(_ value: Double?) -> String { value?.formatted(.percent.precision(.fractionLength(1))) ?? "Unavailable" }
    private func evaluate(_ url: URL) {
        evaluate {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            return try file.read(upToCount: 8 * 1024 * 1024 + 1) ?? Data()
        }
    }
    /// Prepared and imported datasets share one evaluation path.
    private func evaluate(load: @escaping @Sendable () throws -> Data) {
        guard !running, !model.recording, !model.ready else { return }
        guard let minimum = Int(minimumWindows), minimum > 0 else {
            failure = "Minimum windows per class must be a positive integer."; return
        }
        let associationFraction: Double?
        if associationEnabled {
            guard let percent = Double(associationPercent), percent.isFinite, percent > 0, percent <= 100 else {
                failure = "Minimum eligible exposure must be greater than zero and at most 100 percent."; return
            }
            associationFraction = percent / 100
        } else { associationFraction = nil }
        let resampling: EEGSessionResampling.Options?
        do {
            if resamplingEnabled {
                guard let iterations = Int(resamplingIterations), let seed = UInt64(resamplingSeed),
                      let percent = Double(resamplingPercent) else { throw EEGSessionResampling.Failure.invalidOptions }
                let value = EEGSessionResampling.Options(iterations: iterations, seed: seed, centralMass: percent / 100)
                try value.validate(); resampling = value
            } else { resampling = nil }
        } catch { failure = "Enter at least 2 resamples, an unsigned integer seed and a percentage strictly between 0 and 100."; return }
        let directory = model.directory, controls = controlsOnly
        generation += 1;let request=generation
        running = true; artifact = nil; failure = nil; exportMessage = nil
        let worker = Task.detached(priority: .utility) {
            Result {
                try Task.checkCancellation()
                let result = try EEGEvaluationArtifact.run(manifest: load(), store: EEGRecordingStore(directory: directory), profile: profile, controlsOnly: controls, minimumWindowsPerClass: minimum, resampling: resampling, trialAssociationMinimumEligibleFraction: associationFraction)
                try Task.checkCancellation()
                return result
            }
        }
        evaluationWorker = worker
        Task { @MainActor in
            let result = await worker.value
            running = false; evaluationWorker = nil
            guard request == generation else { return }
            guard !worker.isCancelled else { failure = "Evaluation cancelled; no new receipt was produced."; return }
            switch result {
            case .success(let value): artifact = value
            case .failure(let error) where error is CancellationError: failure = "Evaluation cancelled; no new receipt was produced."
            case .failure(let error): failure = "Evaluation rejected: \(error.localizedDescription) [\(error)]"
            }
        }
    }
}

struct EvaluationDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = contents
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
