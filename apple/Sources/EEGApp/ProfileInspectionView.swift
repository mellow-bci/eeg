import SwiftUI
import UniformTypeIdentifiers
import EEGCore

struct ProfileInspectionView: View {
    @State private var importing = false
    @State private var loading = false
    @State private var profile: EEGMentalProfile?
    @State private var failure: String?
    var body: some View {
        Panel(title: "Independent training profile") {
            HStack {
                Button("Open profile", systemImage: "doc.badge.plus") { importing = true }.disabled(loading)
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
                DatasetEvaluationView(profile: profile).id(profile.id)
                ReplayInferenceView(profile: profile).id(profile.id)
            } else {
                Text("Open an eeg.mental-profile.v2 JSON file from the independent offline trainer. Native training and session evaluation are still being implemented.").foregroundStyle(.secondary)
            }
            if let failure { Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(.red).textSelection(.enabled) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .failure(let error): failure = error.localizedDescription
            case .success(let url):
                loading = true; profile = nil; failure = nil
                Task { @MainActor in
                    let result = await Task.detached(priority: .userInitiated) {
                        Result { () throws -> EEGMentalProfile in
                            let access = url.startAccessingSecurityScopedResource()
                            defer { if access { url.stopAccessingSecurityScopedResource() } }
                            let file = try FileHandle(forReadingFrom: url)
                            defer { try? file.close() }
                            let data = try file.read(upToCount: 8 * 1024 * 1024 + 1) ?? Data()
                            return try EEGMentalProfile.load(data: data)
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
}
