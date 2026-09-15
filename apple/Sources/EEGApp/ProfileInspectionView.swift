import SwiftUI
import UniformTypeIdentifiers
import EEGCore
#if os(macOS)
import AppKit
#endif

struct ProfileInspectionView: View {
    @State private var importing = false
    @State private var loading = false
    @Binding var profile: EEGMentalProfile?
    let preparedManifest: Data?
    @State private var failure: String?
    var body: some View {
        Panel(title: "Independent training profile") {
            ProfileLibraryView { profile = $0; failure = nil }
            HStack {
                Button("Open profile", systemImage: "doc.badge.plus") { openDocument() }.disabled(loading || importing)
                if loading { ProgressView().controlSize(.small) }
                Spacer()
                if profile != nil { Button("Close profile") { profile = nil; failure = nil } }
            }
            if let profile {
                Label("Integrity and supported structure verified", systemImage: "checkmark.shield")
                LabeledContent("Participant", value: profile.participantID)
                LabeledContent("Training sessions", value: String(profile.trainingSessions.count))
                LabeledContent("Classes", value: profile.parameters.classes.joined(separator: ", "))
                LabeledContent("Persistent windows", value: String(profile.settings.persistenceWindows))
                Text(profile.id).font(.caption.monospaced()).textSelection(.enabled)
                Label("Experimental · command output disabled", systemImage: "hand.raised")
                Text("Integrity does not verify task labels or physiological accuracy. Opening this file does not change acquisition settings. An offline check can be started below.").font(.callout).foregroundStyle(.secondary)
                DatasetEvaluationView(profile: profile, preparedManifest: preparedManifest).id(profile.id)
                ReplayInferenceView(profile: profile).id(profile.id)
                LiveShadowView(profile: profile).id(profile.id)
            } else {
                Text("Open a versioned experimental profile created here or by the independent offline trainer. Inspect its provenance, then evaluate separate labeled recordings below.").foregroundStyle(.secondary)
            }
            if let failure { Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(.red).textSelection(.enabled) }
        }
        #if !os(macOS)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            receiveDocument(result)
        }
        #endif
    }
    private func openDocument() {
        #if os(macOS)
        importing = true
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            importing = false
            if response == .OK, let url = panel.url { receiveDocument(.success(url)) }
        }
        #else
        importing = true
        #endif
    }
    private func receiveDocument(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error): failure = error.localizedDescription
        case .success(let url):
            loading = true; profile = nil; failure = nil
            Task { @MainActor in
                let result = await Task.detached(priority: .userInitiated) {
                    Result { () throws -> EEGMentalProfile in
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        return try EEGProfileStore.readDocument(url)
                    }
                }.value
                loading = false
                switch result {
                case .success(let value): profile = value
                case .failure(let error): failure = "Profile rejected: \(error)"
                }
            }
        }
    }
}
