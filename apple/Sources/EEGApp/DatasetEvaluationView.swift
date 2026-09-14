import SwiftUI
import UniformTypeIdentifiers
import EEGCore

struct DatasetEvaluationView: View {
    let profile: EEGMentalProfile
    @EnvironmentObject private var model: AcquisitionModel
    @State private var importing = false
    @State private var running = false
    @State private var report: EEGLabeledEvaluation?
    @State private var failure: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text("Evaluate labeled sessions").font(.headline)
            Text("Choose a dataset manifest with evaluation sessions. At least 10 evaluation windows per class are required. Rejected windows remain in the denominator; labels are declarations, not independently verified mental states.").foregroundStyle(.secondary)
            Button("Open dataset and evaluate", systemImage: "chart.bar") { importing = true }
                .disabled(running || model.recording || model.ready)
            if running { ProgressView("Evaluating held-out recordings…") }
            if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
            if let report {
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
                    VStack(alignment: .leading) {
                        Text(condition.replacingOccurrences(of: "_", with: " ")).font(.headline)
                        Text("Eligible: \(exposure.eligibleSeconds.formatted(.number.precision(.fractionLength(2)))) s · Rejected: \(exposure.rejectedSeconds.formatted(.number.precision(.fractionLength(2)))) s · Unarmed: \(exposure.unarmedSeconds.formatted(.number.precision(.fractionLength(2)))) s")
                        Text("Candidate episodes: \(exposure.episodeOnsets) · Carry-ins: \(exposure.carryInCandidates)")
                        Text("Empirical episodes/hour: \(exposure.episodeOnsetsPerHour.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "Unavailable")")
                    }.font(.caption).accessibilityElement(children: .combine)
                }
                ForEach(Array(report.trials.enumerated()), id: \.offset) { _, trial in
                    VStack(alignment: .leading) {
                        Text("\(trial.sessionID) / \(trial.trialID)").font(.headline)
                        Text("Unobserved interval: \(trial.unobservedSeconds.formatted(.number.precision(.fractionLength(2)))) s")
                        Text("Cue-associated candidate latency: \(trial.firstCueAssociatedCandidateLatency.map { $0.formatted(.number.precision(.fractionLength(2))) + " s" } ?? "Unavailable")")
                    }.font(.caption).accessibilityElement(children: .combine)
                }
                Text("Latency is measured from recorded cue completion to candidate input availability, not mental onset or live-system response.").font(.caption).foregroundStyle(.secondary)
                Text("Experimental window-level metrics. Windows within trials are correlated. These values do not establish physiological accuracy, physiologically validated false-activation rates or safe system control. Episode rates have no uncertainty bound yet; carry-in activity makes the rate unavailable.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { selection in
            switch selection {
            case .failure(let error): failure = error.localizedDescription
            case .success(let url): evaluate(url)
            }
        }
    }
    private func percent(_ value: Double?) -> String { value?.formatted(.percent.precision(.fractionLength(1))) ?? "Unavailable" }
    private func evaluate(_ url: URL) {
        guard !running, !model.recording, !model.ready else { return }
        let directory = model.directory
        running = true; report = nil; failure = nil
        Task { @MainActor in
            let result = await Task.detached(priority: .utility) {
                Result { () throws -> EEGLabeledEvaluation in
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let file = try FileHandle(forReadingFrom: url)
                    defer { try? file.close() }
                    let data = try file.read(upToCount: 8 * 1024 * 1024 + 1) ?? Data()
                    let dataset = try EEGTrainingDataset.load(data, store: EEGRecordingStore(directory: directory), settings: profile.settings)
                    return try EEGLabeledEvaluation.run(profile: profile, dataset: dataset)
                }
            }.value
            running = false
            switch result {
            case .success(let value): report = value
            case .failure(let error): failure = "Evaluation rejected: \(error)"
            }
        }
    }
}
