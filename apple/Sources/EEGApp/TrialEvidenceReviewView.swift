import SwiftUI
import EEGCore

/// Read-only inspection of the canonical recovered journal, never relabeling samples.
struct TrialEvidenceReviewView: View {
    @EnvironmentObject private var model: AcquisitionModel
    let recording: EEGRecordingInfo
    @State private var loading = false
    @State private var trials: [EEGTrialEvidence]?
    @State private var failure: String?
    @State private var failureDetails: String?
    @State private var expanded: Bool

    init(recording: EEGRecordingInfo, initiallyExpanded: Bool = false) {
        self.recording = recording
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        DisclosureGroup("Recorded trial evidence", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Reports and review decisions are declarations, not independent proof of mental state. This view requires a finalized recording with a saved trial plan. It does not change labels or accept trials.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Read trial journal") { load() }
                    .disabled(loading || !recording.complete || recording.corrupt || model.recording || model.ready || model.fileOperation != nil)
                if loading { ProgressView("Validating saved trial evidence…") }
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled)
                    if let failureDetails {
                        DisclosureGroup("Technical details") {
                            Text(failureDetails).font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                }
                if let trials {
                    let accepted = trials.filter { $0.phase == .reviewed && $0.accepted }.count
                    Text("\(trials.count) trials recorded · \(accepted) accepted · \(trials.count - accepted) excluded or not accepted")
                        .monospacedDigit()
                    if trials.isEmpty { Text("No trials were started in the saved plan.").foregroundStyle(.secondary) }
                    ForEach(trials, id: \.id) { trial in
                        DisclosureGroup(trial.id) {
                            VStack(alignment: .leading, spacing: 6) {
                                LabeledContent("Participant", value: trial.participantID)
                                LabeledContent("Session ID", value: trial.sessionID)
                                LabeledContent("Requested condition", value: trial.requestedCondition.rawValue.replacingOccurrences(of: "_", with: " "))
                                LabeledContent("State", value: trial.phase.rawValue)
                                LabeledContent("Participant report", value: trial.participantReport?.rawValue ?? "Not recorded")
                                LabeledContent("Reviewer", value: trial.reviewer ?? "Not recorded")
                                LabeledContent("Observed behavior", value: trial.observedBehavior)
                                LabeledContent("Accepted", value: trial.accepted ? "Yes" : "No")
                                if let reason = trial.reviewReason { Text("Review reason: " + reason) }
                                Text("Event times are recording receipt-clock seconds.").font(.caption)
                                ForEach(Array(trial.events.enumerated()), id: \.offset) { _, event in
                                    Text("\(event.at.formatted(.number.precision(.fractionLength(3)))) s · \(event.kind)")
                                        .font(.caption.monospaced()).textSelection(.enabled)
                                    if let detail = event.detail { Text(detail).font(.caption).textSelection(.enabled) }
                                }
                            }.textSelection(.enabled)
                        }
                    }
                }
            }.padding(.vertical, 8)
        }
    }
    private func load() {
        guard !loading, recording.complete, !recording.corrupt, !model.recording, !model.ready else { return }
        loading = true; trials = nil; failure = nil; failureDetails = nil
        let directory = model.directory, url = recording.url
        Task { @MainActor in
            let result = await Task.detached(priority: .utility) {
                Result { try EEGRecordingStore(directory: directory).recoveredTrials(recording: url) }
            }.value
            loading = false
            switch result {
            case .success(let values): trials = values
            case .failure(let error):
                failureDetails = String(describing: error)
                if case EEGRecordingError.missingTrialPlan(_) = error {
                    failure = "This recording has no saved trial plan. It cannot supply planned trials for training. Record a new planned session in Capture trials; keep this recording for signal review."
                } else {
                    failure = "The saved trial evidence could not be verified. This recording has not been accepted for training."
                }
            }
        }
    }
}
