import SwiftUI
import UniformTypeIdentifiers
import EEGCore

struct DatasetTrainingView: View {
    let parentProfile: EEGMentalProfile?
    @State private var retraining = false
    let onSaved: (EEGMentalProfile) -> Void
    @EnvironmentObject private var model: AcquisitionModel
    @State private var importing = false
    @State private var running = false
    @Binding var manifest: Data?
    @Binding var manifestName: String
    @State private var result: String?
    @State private var failure: String?
    var body: some View {
        Panel(title: "Train from recorded trials") {
            Text("Open an eeg.dataset.v1 manifest referencing recordings in this app’s local library. Only accepted, verified trials from independent training sessions are fitted. Evaluation sessions are checked for content reuse and excluded from fitting.").foregroundStyle(.secondary)
            Text("Trial labels and independent-session declarations are supplied by you. Training does not prove intent recognition or enable commands.").font(.callout)
            HStack {
                Button("Open dataset manifest", systemImage: "doc.badge.plus") { importing = true }
                Text(manifestName).font(.caption)
            }.disabled(running)
            Toggle("Retrain from the inspected profile", isOn: $retraining)
                .disabled(parentProfile == nil || running)
            if retraining, let parentProfile {
                Text("Parent: \(parentProfile.id)").font(.caption.monospaced()).textSelection(.enabled)
                Text("Refits from this dataset using saved Processing settings. The parent stays unchanged; prior evaluation is not inherited.").font(.caption)
            }
            Button(retraining ? "Retrain and save new profile" : "Train and save experimental profile", systemImage: "brain") { train() }
                .disabled(manifest == nil || running || model.recording || model.ready || (retraining && parentProfile == nil))
            Text("Uses saved Processing settings. Profiles are saved privately in EEG/Profiles without replacing existing files.").font(.caption).foregroundStyle(.secondary)
            if running { ProgressView("Validating recordings and fitting profile…") }
            if let result { Text(result).textSelection(.enabled) }
            if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
        }
        .onChange(of: parentProfile?.id) { _,_ in retraining = false }
        .eegJSONImporter(isPresented: $importing) { selection in
            switch selection {
            case .failure(let error): failure = error.localizedDescription
            case .success(let url):
                running = true; manifest = nil; result = nil; failure = nil
                Task { @MainActor in
                    let loaded = await Task.detached(priority: .utility) {
                        Result { () throws -> Data in
                            let access = url.startAccessingSecurityScopedResource()
                            defer { if access { url.stopAccessingSecurityScopedResource() } }
                            let file = try FileHandle(forReadingFrom: url)
                            defer { try? file.close() }
                            let data = try file.read(upToCount: 8 * 1024 * 1024 + 1) ?? Data()
                            guard data.count <= 8 * 1024 * 1024 else { throw EEGTrainingDataset.Failure.invalidManifest }
                            return data
                        }
                    }.value
                    running = false
                    switch loaded {
                    case .success(let data): manifest = data; manifestName = url.lastPathComponent
                    case .failure(let error): failure = "Manifest rejected: \(error.localizedDescription) [\(error)]"
                    }
                }
            }
        }
    }
    private func train() {
        guard let data = manifest, !running, !model.recording, !model.ready else { return }
        guard !retraining || parentProfile != nil else { return }
        let parent = retraining ? parentProfile : nil
        let directory = model.directory
        running = true; result = nil; failure = nil
        Task { @MainActor in
            let trained = await Task.detached(priority: .utility) {
                Result { () throws -> (EEGMentalProfile, String) in
                    let root = directory.deletingLastPathComponent()
                    let settings = try ProcessingSettingsStore(directory: root).load()
                    let dataset = try EEGTrainingDataset.load(data, store: EEGRecordingStore(directory: directory), settings: settings)
                    let artifact: EEGProfileCreation.Artifact
                    if let parent {
                        artifact = try EEGProfileCreation.retrain(dataset.records, participantID: dataset.participantID, parent: parent, settings: settings)
                    } else {
                        artifact = try EEGProfileCreation.train(dataset.records, participantID: dataset.participantID, settings: settings)
                    }
                    let profiles = root.appendingPathComponent("Profiles", isDirectory: true)
                    let store = EEGProfileStore(directory: profiles)
                    let path = profiles.appendingPathComponent(artifact.profile.id + ".json")
                    let saved = try store.save(artifact)
                    return (saved, "Saved experimental profile from \(dataset.records.count) usable training windows. Rejected labeled windows: \(dataset.sessions.reduce(0) { $0 + $1.rejectedWindows }).\n\(path.path)\nProfile opened below for a separate evaluation.")
                }
            }.value
            running = false
            switch trained {
            case .success(let saved): result = saved.1; onSaved(saved.0)
            case .failure(let error): failure = "Training rejected: \(error.localizedDescription) [\(error)]"
            }
        }
    }
}
