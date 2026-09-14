import SwiftUI
import UniformTypeIdentifiers
import EEGCore

private struct ProcessingSettingsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(settings: ProcessingSettings) throws { data = try settings.jsonData() }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw ProcessingSettingsError.invalid("Invalid settings document.") }
        _ = try JSONDecoder().decode(ProcessingSettings.self, from: data)
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/// Self-contained settings workspace. It never starts acquisition or model training.
struct ProcessingSettingsView: View {
    @State private var selected = "20"
    @State private var components = "8"
    @State private var variance = "0.05"
    @State private var score = "0.9"
    @State private var margin = "0.25"
    @State private var persistence = "2"
    @State private var budgetEnabled = false
    @State private var budget = "10000"
    @State private var store: ProcessingSettingsStore?
    @State private var message: String?
    @State private var error: String?
    @State private var importing = false
    @State private var exporting = false
    @State private var document: ProcessingSettingsDocument?
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Processing preferences", systemImage: "slider.horizontal.3")
                        .font(.title2.bold())
                    Text("Configure the independent processing workflow. Your settings stay on this device and use the same JSON format as the research CLI.")
                        .foregroundStyle(.secondary)
                    Label("Experimental · external actions remain disabled", systemImage: "flask")
                        .font(.callout).foregroundStyle(.orange)
                }.padding(.vertical, 6)
            }
            Section {
                numberField("Selected features", text: $selected, hint: "1–70")
                numberField("PCA components", text: $components, hint: "1–selected features")
                numberField("Variance floor", text: $variance, hint: "Greater than 0")
            } header: { Label("Feature representation", systemImage: "waveform.path") }
              footer: { Text("Controls training-only feature selection, dimensionality reduction and Gaussian regularization. The 14-channel spectral recipe remains fixed and independently gated.") }
            Section {
                numberField("Score threshold", text: $score, hint: "Greater than 0, up to 1")
                numberField("Minimum score margin", text: $margin, hint: "0–1")
                numberField("Persistent windows", text: $persistence, hint: "At least 1")
            } header: { Label("Candidate rejection", systemImage: "line.3.horizontal.decrease.circle") }
              footer: { Text("Class scores are uncalibrated. More persistent windows require more consecutive evidence; each complete window spans about two seconds. These values do not establish physiological validity or enable a command.") }
            Section {
                Toggle("Use an explicit training window budget", isOn: $budgetEnabled)
                if budgetEnabled { numberField("Maximum training windows", text: $budget, hint: "Positive integer") }
                if !budgetEnabled { Label("No software training window cap", systemImage: "infinity").foregroundStyle(.secondary) }
            } header: { Label("Training resources", systemImage: "memorychip") }
              footer: { Text("The default has no training window cap. An optional budget is a resource safeguard, not a recording limit. Memory, storage and execution time still constrain processing.") }
            Section {
                HStack(spacing: 14) {
                    Button("Save settings", systemImage: "checkmark.circle.fill", action: save)
                        .buttonStyle(.borderedProminent).disabled(store == nil)
                    Button("Reset draft to defaults", action: { apply(ProcessingSettings()); error = nil; message = "Defaults restored in the draft. Save to apply." })
                }
                HStack(spacing: 14) {
                    Button("Import JSON", systemImage: "square.and.arrow.down", action: { importing = true })
                    Button("Export JSON", systemImage: "square.and.arrow.up", action: prepareExport)
                }
                if let error { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).textSelection(.enabled) }
                if let message { Text(message).foregroundStyle(.secondary).textSelection(.enabled) }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Import and reset update the draft. Save writes one local configuration file; export writes the current validated draft. Existing profiles are unchanged and require explicit retraining to use different settings.")
                    Text("Calibration uses these saved settings when training a new experimental profile. Existing profiles retain their own settings; saving here does not run or modify a model.")
                    if let store { Text(store.file.path).font(.caption.monospaced()).textSelection(.enabled) }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Processing")
        .task { if !loaded { loaded = true; load() } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let settings = try ProcessingSettingsStore.read(url)
                apply(settings); error = nil; message = "Imported validated settings. Review the draft and save to apply."
            } catch { self.error = error.localizedDescription; message = nil }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "eeg-processing-settings.json") { result in
            switch result {
            case .success: error = nil; message = "Settings JSON exported."
            case .failure(let failure): error = failure.localizedDescription; message = nil
            }
        }
    }
    private func numberField(_ title: String, text: Binding<String>, hint: String) -> some View {
        LabeledContent(title) {
            TextField(hint, text: text).textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing).monospacedDigit().frame(minWidth: 110, maxWidth: 220)
                .accessibilityLabel(title)
        }
    }
    private func draft() throws -> ProcessingSettings {
        guard let featureCount = Int(selected), let componentCount = Int(components),
              let windowCount = Int(persistence), let varianceValue = Double(variance),
              let scoreValue = Double(score), let marginValue = Double(margin) else {
            throw ProcessingSettingsError.invalid("Enter valid numbers in every processing field.")
        }
        var settings = ProcessingSettings()
        settings.selectedFeatures = featureCount; settings.pcaComponents = componentCount
        settings.persistenceWindows = windowCount; settings.varianceFloor = varianceValue
        settings.scoreThreshold = scoreValue; settings.marginThreshold = marginValue
        if budgetEnabled {
            guard let maximum = Int(budget) else { throw ProcessingSettingsError.invalid("Training budget must be a positive integer.") }
            settings.maxTrainingWindows = maximum
        }
        try settings.validate()
        return settings
    }
    private func apply(_ settings: ProcessingSettings) {
        selected = String(settings.selectedFeatures); components = String(settings.pcaComponents)
        variance = String(settings.varianceFloor); score = String(settings.scoreThreshold)
        margin = String(settings.marginThreshold); persistence = String(settings.persistenceWindows)
        budgetEnabled = settings.maxTrainingWindows != nil
        budget = settings.maxTrainingWindows.map(String.init) ?? "10000"
    }
    private func load() {
        do {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("EEG", isDirectory: true)
            let created = try ProcessingSettingsStore(directory: directory)
            store = created
            apply(try created.load())
        } catch { self.error = error.localizedDescription }
    }
    private func save() {
        do {
            guard let store else { throw ProcessingSettingsError.invalid("Settings storage is unavailable.") }
            try store.save(draft()); error = nil; message = "Processing settings saved locally. Existing profiles are unchanged."
        } catch { self.error = error.localizedDescription; message = nil }
    }
    private func prepareExport() {
        do { document = try ProcessingSettingsDocument(settings: draft()); error = nil; exporting = true }
        catch { self.error = error.localizedDescription; message = nil }
    }
}
