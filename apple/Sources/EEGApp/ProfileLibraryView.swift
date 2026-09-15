import SwiftUI
import EEGCore

struct ProfileLibraryView: View {
    @EnvironmentObject private var model: AcquisitionModel
    let revision: Int
    let onOpen: (String) -> Void
    @State private var entries: [EEGProfileStore.Entry] = []
    @State private var busy = false
    @State private var refreshPending = false
    @State private var failure: String?
    private var store: EEGProfileStore { EEGProfileStore(directory: model.directory.deletingLastPathComponent().appendingPathComponent("Profiles", isDirectory: true)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Saved on this device").font(.headline)
                Spacer()
                Button("Refresh profiles", systemImage: "arrow.clockwise") { refresh() }.disabled(busy)
            }
            if busy { ProgressView("Reading local profiles…") }
            if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
            if entries.isEmpty && !busy { Text("No saved profiles listed. Train from recordings or open an existing profile document.").foregroundStyle(.secondary) }
            ForEach(entries) { entry in
                HStack {
                    VStack(alignment: .leading) {
                        Text(entry.id).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                        Text(entry.modified, style: .date).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Inspect") { onOpen(entry.id) }.disabled(busy)
                        .accessibilityLabel("Inspect profile \(entry.id)")
                }
            }
            Text("Listing is not validation. Inspect checks the saved contents and identity before evaluation.").font(.caption).foregroundStyle(.secondary)
            Divider()
        }.task { refresh() }
        .onChange(of: revision) { _, _ in refresh() }
    }
    private func refresh() {
        guard !busy else { refreshPending = true; return }
        refreshPending = false
        let store = store
        busy = true; failure = nil
        Task { @MainActor in
            let result = await Task.detached(priority: .utility) { Result { try store.entries() } }.value
            busy = false
            switch result {
            case .success(let values): entries = values
            case .failure(let error): entries = []; failure = "Profile library unavailable: \(error)"
            }
            if refreshPending { refresh() }
        }
    }
}
