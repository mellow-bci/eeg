import SwiftUI
import EEGCore

struct ReplayInferenceView: View {
    let profile: EEGMentalProfile
    @EnvironmentObject private var model: AcquisitionModel
    @State private var recordingName = ""
    @State private var sessionID = ""
    @State private var participantID = ""
    @State private var maximumWindows = 10000
    @State private var running = false
    @State private var report: EEGReplayInferenceReport?
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text("Offline inference check").font(.headline)
            Text("Select a completed recording and enter its participant and session identity. These are your assertions, not verified labels. This check produces experimental candidates and rejection reasons, not accuracy or actionable commands.").foregroundStyle(.secondary)
            Picker("Recording", selection: $recordingName) {
                Text("Choose recording").tag("")
                ForEach(model.recordings.filter { $0.complete && !$0.corrupt }) { item in Text(item.name).tag(item.name) }
            }
            TextField("Participant identity", text: $participantID)
            TextField("Held-out session identity", text: $sessionID)
            HStack {
                Text("Maximum windows")
                TextField("Maximum windows", value: $maximumWindows, format: .number).frame(maxWidth: 130)
            }
            Text("Processing stops with an error if this limit is exceeded; it never returns a truncated report.").font(.caption).foregroundStyle(.secondary)
            Button("Run offline check", systemImage: "play") { run() }
                .disabled(running || model.recording || model.ready || recordingName.isEmpty || participantID.isEmpty || sessionID.isEmpty || maximumWindows <= 0)
            if running { ProgressView("Validating recording and extracting features…") }
            if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
            if let report {
                LabeledContent("Analyzed windows", value: String(report.windows.count))
                LabeledContent("Experimental candidates", value: String(report.windows.filter { $0.candidate != nil }.count))
                Text("No reliable command · system control disabled").font(.headline)
                Text("Recording SHA-256: \(report.recordingSHA256)").font(.caption.monospaced()).textSelection(.enabled)
                Text("Participant: \(report.participantID) · Session: \(report.sessionID)").font(.caption)
                ForEach(Array(report.windows.prefix(100).enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top) {
                        Text("\(row.ordinal + 1)").monospacedDigit().frame(width: 45, alignment: .trailing)
                        Text(row.reasons.joined(separator: ", "))
                        Spacer()
                        if let candidate = row.candidate { Text("Experimental: \(candidate)") }
                    }.font(.caption)
                }
                if report.windows.count > 100 { Text("Showing the first 100 windows; totals include all analyzed windows.").font(.caption) }
            }
        }
        .disabled(running)
        .onChange(of: recordingName) { _, _ in report = nil; failure = nil }
    }

    private func run() {
        guard !running, !model.recording, !model.ready else { return }
        let directory = model.directory, url = directory.appendingPathComponent(recordingName)
        let participant = participantID, session = sessionID, limit = maximumWindows
        running = true; report = nil; failure = nil
        Task { @MainActor in
            let result = await Task.detached(priority: .utility) {
                Result { try EEGReplayInference.run(store: EEGRecordingStore(directory: directory), recording: url,
                    profile: profile, participantID: participant, sessionID: session, maximumWindows: limit) }
            }.value
            running = false
            switch result {
            case .success(let value): report = value
            case .failure(let error): failure = "Offline check rejected: \(error.localizedDescription)"
            }
        }
    }
}
