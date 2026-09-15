import SwiftUI
import UniformTypeIdentifiers
import EEGCore

struct DatasetBuilderView: View {
    @EnvironmentObject private var model: AcquisitionModel
    @Binding var manifest: Data?
    @Binding var manifestName: String
    private enum Selection: String, CaseIterable { case skip, train, evaluation }
    @State private var choices: [String:Selection] = [:]
    @State private var declarations: [String:String] = [:]
    @State private var running = false
    @State private var exporting = false
    @State private var exportData = Data()
    @State private var message: String?
    @State private var failure: String?
    var body: some View {
        Panel(title: "Build a dataset from reviewed recordings") {
            Text("Choose independent recordings and assign each to training or evaluation before fitting. Only planned, reviewed trials are included. Changing a selection clears the prepared dataset.").foregroundStyle(.secondary)
            if recordings.isEmpty { Text("No finalized recordings available.") }
            ForEach(recordings) { info in
                VStack(alignment: .leading, spacing: 8) {
                    Text(info.name).font(.caption.monospaced()).textSelection(.enabled)
                    Picker("Dataset use", selection: Binding(get:{ choices[info.id] ?? .skip },set:{ choices[info.id]=$0 })) {
                        Text("Not included").tag(Selection.skip)
                        Text("Training").tag(Selection.train)
                        Text("Evaluation").tag(Selection.evaluation)
                    }
                    if choices[info.id] != nil && choices[info.id] != .skip {
                        TextField("Describe why this is an independent acquisition",text:Binding(get:{ declarations[info.id] ?? "" },set:{ declarations[info.id]=$0 }))
                    }
                }.padding(.vertical, 6)
            }
            Text("Renaming or splitting one recording does not create independence. Keep evaluation sessions out of tuning; this declaration does not prove independence.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Validate and prepare dataset") { prepare() }.disabled(running || model.ready || model.recording || selectedCount == 0)
                Button("Export prepared manifest") {
                    guard let manifest else { return }
                    exportData=manifest;exporting=true
                }.disabled(manifest == nil || running)
            }
            if running { ProgressView("Recovering evidence and checking recorded windows…") }
            if let message { Text(message).textSelection(.enabled) }
            if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
        }
        .disabled(running)
        .onChange(of: choices) { _,_ in invalidate() }
        .onChange(of: declarations) { _,_ in invalidate() }
        .fileExporter(isPresented:$exporting,document:DatasetManifestDocument(data:exportData),contentType:.json,defaultFilename:"eeg-dataset.json") { result in
            switch result {
            case .success: message="Manifest exported. Keep its original recordings for replay."
            case .failure(let error): failure="Export failed: " + error.localizedDescription
            }
        }
    }
    private var recordings: [EEGRecordingInfo] { model.recordings.filter { $0.complete && !$0.corrupt } }
    private var selectedCount: Int { choices.values.filter { $0 != .skip }.count }
    private func invalidate() { manifest=nil;manifestName="";message=nil;failure=nil }
    private func prepare() {
        guard !running,!model.ready,!model.recording else { return }
        let selected=recordings.filter { choices[$0.id] != nil && choices[$0.id] != .skip }
        guard selected.count == selectedCount else { failure="A selected recording is no longer available. Refresh your selection.";return }
        let sources=selected.map { EEGTrialDatasetExport.Source(recording:$0.url,split:choices[$0.id] == .train ? .train : .evaluation,independenceDeclaration:declarations[$0.id] ?? "") }
        let directory=model.directory
        invalidate();running=true
        Task { @MainActor in
            let result=await Task.detached(priority:.utility) {
                Result { try EEGTrialDatasetExport.manifest(sources:sources,store:EEGRecordingStore(directory:directory)) }
            }.value
            running=false
            switch result {
            case .success(let data):
                manifest=data;manifestName="Prepared from reviewed recordings"
                message="Dataset prepared from \(sources.count) recordings. It is available to the training controls below; no training has started."
            case .failure(let error): failure="Dataset rejected: \(error)"
            }
        }
    }
}
private struct DatasetManifestDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(data: Data) { self.data=data }
    init(configuration: ReadConfiguration) throws {
        guard let data=configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data=data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents:data) }
}
