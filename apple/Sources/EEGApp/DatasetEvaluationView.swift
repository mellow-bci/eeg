import SwiftUI
import UniformTypeIdentifiers
import EEGCore

struct DatasetEvaluationView: View {
    let profile: EEGMentalProfile
    let preparedManifest: Data?
    @State private var generation = 0
    @EnvironmentObject private var model: AcquisitionModel
    @State private var controlsOnly = false
    @State private var importing = false
    @State private var running = false
    @State private var artifact: EEGEvaluationArtifact?
    @State private var exporting = false
    @State private var exportMessage: String?
    private var report: EEGLabeledEvaluation? { artifact?.report }
    @State private var failure: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text("Evaluate labeled sessions").font(.headline)
            Toggle("Controls-only evaluation", isOn: $controlsOnly).disabled(running)
                .onChange(of: controlsOnly) { _, _ in artifact = nil; failure = nil; exportMessage = nil }
            Text(controlsOnly ? "Only neutral-labeled control conditions are accepted. Task recall cannot be measured from control trials." : "Full evaluation requires at least 10 windows per class.").font(.caption)
            Text("Choose a dataset manifest with evaluation sessions. Rejected windows remain in the denominator; labels are declarations, not independently verified mental states.").foregroundStyle(.secondary)
            Button("Evaluate prepared dataset", systemImage: "chart.bar") {
                if let data=preparedManifest { evaluate { data } }
            }.disabled(preparedManifest == nil || running || model.recording || model.ready)
            Button("Open dataset and evaluate", systemImage: "doc.badge.plus") { importing = true }
                .disabled(running || model.recording || model.ready)
            if running { ProgressView("Evaluating held-out recordings…") }
            if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
            if let report {
                Button("Export evaluation JSON", systemImage: "square.and.arrow.up") { exporting = true }
                if let exportMessage { Text(exportMessage).font(.caption) }
                LabeledContent("Scope", value: report.controlsOnly ? "Controls only" : "Full labeled evaluation")
                if !report.controlConditionsWithoutEligibleExposure.isEmpty {
                    Text("No eligible control exposure: " + report.controlConditionsWithoutEligibleExposure.map { $0.replacingOccurrences(of:"_",with:" ") }.joined(separator:", ")).font(.callout)
                }
                Text("Control coverage indicates presence only. Adequate duration and real artifact-response validation are still required.").font(.caption).foregroundStyle(.secondary)
                LabeledContent("Evaluation windows", value: String(report.predictions.count))
                LabeledContent("Rejected", value: report.rejectionFraction.formatted(.percent.precision(.fractionLength(1))))
                ForEach(report.metrics.keys.sorted(), id: \.self) { label in
                    let metric = report.metrics[label]!
                    VStack(alignment: .leading) {
                        Text(label).font(.headline)
                        Text("TP \(metric.truePositive) · FP \(metric.falsePositive) · FN \(metric.falseNegative)").monospacedDigit()
                        Text("Precision: \(percent(metric.precision)) · Recall: \(percent(metric.recall))")
                    }.accessibilityElement(children: .combine)
                }
                ForEach(report.conditions.keys.sorted(), id: \.self) { condition in
                    let exposure = report.conditions[condition]!
                    exposureSummary(condition: condition, exposure: exposure)
                }
                DisclosureGroup("Results by session") {
                    let metricsBySession = report.sessionMetrics
                    Text("Compare individual sessions before interpreting pooled rates.").font(.caption)
                    ForEach(report.sessionConditions.keys.sorted(), id: \.self) { session in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(session).font(.headline).textSelection(.enabled)
                            let metrics = metricsBySession[session] ?? [:]
                            ForEach(metrics.keys.sorted(),id: \.self) { label in
                                let metric = metrics[label]!
                                Text("\(label): precision \(percent(metric.precision)) · recall \(percent(metric.recall)) · TP \(metric.truePositive) / FP \(metric.falsePositive) / FN \(metric.falseNegative)").font(.caption).monospacedDigit()
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
                        Text("Unobserved interval: \(trial.unobservedSeconds.formatted(.number.precision(.fractionLength(2)))) s")
                        Text("Cue-associated candidate latency: \(trial.firstCueAssociatedCandidateLatency.map { $0.formatted(.number.precision(.fractionLength(2))) + " s" } ?? "Unavailable")")
                    }.font(.caption).accessibilityElement(children: .combine)
                }
                Text("Latency is measured from recorded cue completion to candidate input availability, not mental onset or live-system response.").font(.caption).foregroundStyle(.secondary)
                Text("Experimental window-level metrics. Windows within trials are correlated. These values do not establish physiological accuracy, physiologically validated false-activation rates or safe system control. Poisson bounds assume a constant independent event rate; clustered events weaken that assumption. Carry-in activity makes rates unavailable.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: preparedManifest) { _,_ in generation += 1;artifact=nil;failure=nil;exportMessage=nil }
        .eegJSONImporter(isPresented: $importing) { selection in
            switch selection {
            case .failure(let error): failure = error.localizedDescription
            case .success(let url): evaluate(url)
            }
        }
        .fileExporter(isPresented: $exporting, document: EvaluationDocument(data: artifact?.data ?? Data()), contentType: .json, defaultFilename: "eeg-evaluation.json") { result in
            switch result {
            case .success: exportMessage = "Evaluation receipt exported. Keep the matching profile and original recordings for reproduction."
            case .failure(let error): failure = "Export failed: \(error.localizedDescription)"
            }
        }
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
        let directory = model.directory, controls = controlsOnly
        generation += 1;let request=generation
        running = true; artifact = nil; failure = nil; exportMessage = nil
        Task { @MainActor in
            let result = await Task.detached(priority: .utility) {
                Result { try EEGEvaluationArtifact.run(manifest: load(), store: EEGRecordingStore(directory: directory), profile: profile, controlsOnly: controls) }
            }.value
            running = false
            guard request == generation else { return }
            switch result {
            case .success(let value): artifact = value
            case .failure(let error): failure = "Evaluation rejected: \(error.localizedDescription) [\(error)]"
            }
        }
    }
}

private struct EvaluationDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = contents
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
