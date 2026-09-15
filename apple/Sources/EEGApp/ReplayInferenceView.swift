import SwiftUI
import EEGCore

struct ReplayInferenceView: View {
    let profile: EEGMentalProfile
    @EnvironmentObject private var model: AcquisitionModel
    @State private var recordingName = ""
    @State private var sessionID = ""
    @State private var participantID = ""
    @State private var maximumRuns = 1024
    @State private var maximumWindows = 10000
    @State private var running = false
    @State private var report: EEGReplayInferenceReport?
    @State private var shadowCatalog: EEGShadowVerification.Catalog?
    @State private var shadowRunID = ""
    @State private var shadowReport: EEGShadowVerification.Report?
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
            Divider()
            Text("Verify recorded live outputs").font(.headline)
            TextField("Maximum runs to list",value:$maximumRuns,format:.number)
            Button("Load recorded runs") { loadShadowRuns() }
                .disabled(running || model.recording || model.ready || recordingName.isEmpty || maximumRuns<=0)
            if let shadowCatalog {
                Picker("Recorded run",selection:$shadowRunID) {
                    Text("Choose a run").tag("")
                    ForEach(shadowCatalog.runs.filter {$0.profileID==profile.id}) { run in
                        Text(run.sessionID + " · " + run.id).tag(run.id)
                    }
                }
                if !shadowCatalog.runs.contains(where:{$0.profileID==profile.id}) {
                    Text("No runs for this profile in the selected recording.").font(.caption)
                }
            }
            Text("Replays this run from its recorded start boundary. A match checks software consistency, not physiological accuracy or authenticity.").font(.caption).foregroundStyle(.secondary)
            Button("Compare recorded outputs") { verifyShadow() }
                .disabled(running || model.recording || model.ready || recordingName.isEmpty || shadowRunID.isEmpty || maximumWindows<=0)
            if let shadowReport {
                Text(shadowReport.completeMatch ? "Recorded outputs match replay" : "Comparison incomplete or different").font(.headline)
                switch shadowReport.implementationStatus {
                case .matchingSource: Text("EEGCore source matches this build.").font(.caption)
                case .differentSource: Text("Recorded with different EEGCore source. Output agreement does not establish the same implementation.").font(.caption)
                case .unavailable: Text("Recorded implementation is unknown; source identity was not captured.").font(.caption)
                }
                if let source = shadowReport.recordedImplementationSHA256 {
                    Text("Recorded source: " + source).font(.caption.monospaced()).textSelection(.enabled)
                }
                LabeledContent("Replay / recorded windows",value:"\(shadowReport.replayWindows) / \(shadowReport.recordedWindows)")
                LabeledContent("Mismatched windows",value:String(shadowReport.mismatchedOrdinals.count))
                LabeledContent("Missing outputs",value:String(shadowReport.missingOrdinals.count))
                LabeledContent("Stop reason",value:shadowReport.stopReason ?? "No stop recorded")
                Text(shadowReport.recordingSHA256).font(.caption.monospaced()).textSelection(.enabled)
                Text("System control remains disabled.").font(.caption)
            }
            if running { ProgressView("Validating recording and extracting features…") }
            if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
            if let report {
                LabeledContent("Analyzed windows", value: String(report.windows.count))
                LabeledContent("Experimental candidates", value: String(report.windows.filter { $0.candidate != nil }.count))
                LabeledContent("Neutral predictions", value: String(report.windows.filter { $0.interpretation == .neutral }.count))
                LabeledContent("Rejected windows", value: String(report.windows.filter { $0.interpretation == .rejected }.count))
                Text("No reliable command · system control disabled").font(.headline)
                Text("Recording SHA-256: \(report.recordingSHA256)").font(.caption.monospaced()).textSelection(.enabled)
                Text("EEG content SHA-256: \(report.eegContentSHA256)").font(.caption.monospaced()).textSelection(.enabled)
                Text("Participant: \(report.participantID) · Session: \(report.sessionID)").font(.caption)
                ForEach(Array(report.windows.prefix(100).enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top) {
                        Text("\(row.ordinal + 1)").monospacedDigit().frame(width: 45, alignment: .trailing)
                        Text(row.reasons.joined(separator: ", "))
                        Spacer()
                        Text(row.interpretationLabel)
                    }.font(.caption)
                }
                if report.windows.count > 100 { Text("Showing the first 100 windows; totals include all analyzed windows.").font(.caption) }
            }
        }
        .disabled(running)
        .onChange(of: recordingName) { _, _ in report = nil; shadowReport=nil; shadowCatalog=nil; shadowRunID=""; failure = nil }
        .onChange(of: shadowRunID) { _, _ in shadowReport=nil }
    }

    private func loadShadowRuns() {
        guard !running,!model.recording,!model.ready,!recordingName.isEmpty,maximumRuns>0 else {return}
        let directory=model.directory,url=directory.appendingPathComponent(recordingName)
        let runLimit=maximumRuns
        running=true;shadowCatalog=nil;shadowRunID="";shadowReport=nil;failure=nil
        Task { @MainActor in
            let result=await Task.detached(priority:.utility) {
                Result {try EEGShadowVerification.catalog(store:EEGRecordingStore(directory:directory),recording:url,maximumRuns:runLimit)}
            }.value
            running=false
            switch result {
            case .success(let value):shadowCatalog=value
            case .failure(let error):failure="Run discovery rejected: \(error)"
            }
        }
    }
    private func verifyShadow() {
        guard !running,!model.recording,!model.ready,let shadowCatalog,
              shadowCatalog.runs.contains(where:{$0.id==shadowRunID && $0.profileID==profile.id}) else {return}
        let directory=model.directory,url=directory.appendingPathComponent(recordingName)
        let runID=shadowRunID,limit=maximumWindows
        running=true;shadowReport=nil;report=nil;failure=nil
        Task { @MainActor in
            let result=await Task.detached(priority:.utility) {
                Result {try EEGShadowVerification.run(store:EEGRecordingStore(directory:directory),recording:url,
                    profile:profile,runID:runID,maximumWindows:limit,expectedRecordingSHA256:shadowCatalog.recordingSHA256)}
            }.value
            running=false
            switch result {
            case .success(let value):shadowReport=value
            case .failure(let error):failure="Shadow comparison rejected: \(error)"
            }
        }
    }
    private func run() {
        guard !running, !model.recording, !model.ready else { return }
        let directory = model.directory, url = directory.appendingPathComponent(recordingName)
        let participant = participantID, session = sessionID, limit = maximumWindows
        running = true; report = nil; shadowReport=nil; failure = nil
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
