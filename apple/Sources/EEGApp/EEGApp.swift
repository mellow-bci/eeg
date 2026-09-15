import SwiftUI
import EEGCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

@main
struct EEGApplication: App {
    @StateObject private var model = AcquisitionModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup("Signal workspace") {
            WorkspaceView().environmentObject(model).onOpenURL { model.importRawCapture($0) }
            #if os(macOS)
                .frame(minWidth: 760, minHeight: 600)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.prepareForTermination() }
            #else
                .onChange(of: scenePhase) { _, phase in if phase == .background { model.prepareForTermination() } }
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1380, height: 920)
        #endif
    }
}

enum Workspace: String, CaseIterable, Identifiable {
    case live = "Live signals", recordings = "Recordings", analysis = "Spectrum", calibration = "Calibration", settings = "Processing", system = "Diagnostics"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .live: return "waveform.path.ecg"
        case .recordings: return "tray.full"
        case .analysis: return "chart.xyaxis.line"
        case .calibration: return "scope"
        case .settings: return "slider.horizontal.3"
        case .system: return "stethoscope"
        }
    }
}

struct WorkspaceView: View {
    @EnvironmentObject var model: AcquisitionModel
    @State private var selection: Workspace? = .live
    @State private var inspector = false
    @State private var importing = false
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Workspace") { sidebarItem(.live); sidebarItem(.recordings); sidebarItem(.analysis) }
                Section("Research") { sidebarItem(.calibration); sidebarItem(.settings) }
                Section("Device") { sidebarItem(.system) }
            }
            .listStyle(.sidebar)
            .navigationTitle("EEG")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
            .safeAreaInset(edge: .bottom) {
                Label("Stored on this device", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary).padding()
            }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    status
                    switch selection ?? .live {
                    case .live: LiveView()
                    case .recordings: LibraryView()
                    case .analysis: SpectrumAnalysisView()
                    case .calibration: CalibrationView()
                    case .settings: ProcessingSettingsView()
                    case .system: SystemView()
                    }
                }.padding(24).frame(maxWidth: 1400, alignment: .leading).frame(maxWidth: .infinity)
            }
            .navigationTitle((selection ?? .live).rawValue)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { importing = true } label: { Label("Import capture", systemImage: "square.and.arrow.down") }
                        .disabled(model.ready || model.recording || model.fileOperation != nil).help("Import a raw BLE capture JSON")
                    if model.ready {
                        Button { model.recording ? model.stopRecording() : model.startRecording() } label: {
                            Label(model.recording ? "Stop recording" : "Record", systemImage: model.recording ? "stop.circle.fill" : "record.circle")
                        }.tint(model.recording ? .red : .accentColor).disabled(model.playback || model.fileOperation != nil)
                    }
                    Button { inspector.toggle() } label: { Label("Signal inspector", systemImage: "sidebar.right") }.help("Show signal provenance and recent events")
                }
            }
            #if os(visionOS)
            .sheet(isPresented: $inspector) {
                NavigationStack { SignalInspector().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { inspector = false } } } }.frame(minWidth: 340, minHeight: 550)
            }
            #else
            .inspector(isPresented: $inspector) { SignalInspector().inspectorColumnWidth(min: 270, ideal: 310, max: 370) }
            #endif
        }
        .eegJSONImporter(isPresented: $importing) { result in
            do { model.importRawCapture(try result.get()) } catch { model.message = error.localizedDescription }
        }
        .onChange(of: model.playback) { _, value in if value { selection = .recordings } }
        .alert("EEG", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK") { model.message = nil }
        } message: { Text(model.message ?? "") }
    }
    private func sidebarItem(_ item: Workspace) -> some View { Label(item.rawValue, systemImage: item.icon).tag(item) }
    private var status: some View {
        HStack(spacing: 12) {
            Image(systemName: model.playback ? "play.rectangle" : model.ready ? "dot.radiowaves.left.and.right" : "sensor.tag.radiowaves.forward")
                .font(.title2).foregroundStyle(model.transportStable ? .teal : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.phase).font(.headline)
                Text(model.playback ? "Recorded source · read-only review" : "Local acquisition · raw notifications preserved").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let operation = model.fileOperation { ProgressView().controlSize(.small); Text(operation).font(.caption) }
            if model.recording { Label("Recording", systemImage: "record.circle.fill").font(.callout.weight(.semibold)).foregroundStyle(.red) }
        }.accessibilityElement(children: .combine)
    }
}

struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { Text(title).font(.headline); content }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))
    }
}
struct PageTitle: View {
    let title: String; let detail: String
    var body: some View { VStack(alignment: .leading, spacing: 7) { Text(title).font(.largeTitle.bold()); Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) } }
}
struct Metric: View {
    let title: String; let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.title2.weight(.semibold).monospacedDigit()) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12)).accessibilityElement(children: .combine)
    }
}
struct LiveView: View {
    @EnvironmentObject var model: AcquisitionModel
    @State private var marker = ""
    var body: some View {
        Panel(title: "Acquisition") {
            ViewThatFits(in: .horizontal) {
                HStack { deviceIdentity; Spacer(); deviceActions }
                VStack(alignment: .leading, spacing: 14) { deviceIdentity; deviceActions }
            }
            if !model.devices.isEmpty && !model.ready {
                ForEach(model.devices) { device in
                    HStack {
                        VStack(alignment: .leading) { Text(device.name).font(.callout.weight(.medium)); Text(device.id.uuidString).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1) }
                        Spacer(); Button("Connect") { model.connect(device) }.buttonStyle(.bordered).disabled(model.fileOperation != nil)
                    }
                }
            }
        }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 12) {
            Metric(title: model.playback ? "Recorded samples" : "Received samples", value: model.sampleCount.formatted())
            Metric(title: "Transport", value: model.playback ? "Replay" : model.transportStable ? "Stable" : "Recovering / offline")
            Metric(title: model.playback ? "Page samples" : "Decoder rejections", value: (model.playback ? model.samples.count : model.decodeErrors).formatted())
        }
        WaveformWorkbench(samples: model.samples, title: model.playback ? "Recorded signal" : "Live signal")
        Panel(title: "Event markers") {
            HStack {
                TextField("Describe this event", text: $marker).textFieldStyle(.roundedBorder).onSubmit(addMarker)
                Button(action: addMarker) { Label("Mark", systemImage: "bookmark") }.disabled(!model.recording || marker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Markers are timestamped in the same local recording. Freezing the display does not stop recording.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var deviceIdentity: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("EPOC X", systemImage: "sensor.tag.radiowaves.forward").font(.title3.weight(.semibold))
            Text(model.ready ? "Bluetooth connected · notifications active" : "Power on your headset nearby, then find and connect it.").font(.callout).foregroundStyle(.secondary)
        }
    }
    private var deviceActions: some View {
        HStack {
            if model.ready { Button("Disconnect") { model.disconnect() } }
            else { Button(model.scanning ? "Scanning…" : "Find headset") { model.scan() }.disabled(model.scanning || model.fileOperation != nil) }
            Button(model.recording ? "Stop recording" : "Record") { model.recording ? model.stopRecording() : model.startRecording() }
                .buttonStyle(.borderedProminent).tint(model.recording ? .red : .accentColor).disabled(!model.ready || model.playback || model.fileOperation != nil)
        }
    }
    private func addMarker() { guard model.recording, !marker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }; model.annotate(marker); marker = "" }
}

struct LibraryView: View {
    @EnvironmentObject var model: AcquisitionModel
    @State private var query = ""
    @State private var filter = "All"
    @State private var signalSelection: WaveformSelection?
    #if !os(macOS)
    @State private var shareURL: URL?
    #endif
    private var recordings: [EEGRecordingInfo] {
        model.recordings.filter { (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) && (filter == "All" || (filter == "Finalized" ? $0.complete : !$0.complete)) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search recordings", text: $query).textFieldStyle(.roundedBorder).accessibilityLabel("Search recordings by filename")
            HStack {
                Picker("Status", selection: $filter) { Text("All").tag("All"); Text("Finalized").tag("Finalized"); Text("Needs review").tag("Needs review") }.frame(maxWidth: 210)
                Spacer()
                Button { model.refreshRecordings() } label: { Label("Refresh", systemImage: "arrow.clockwise") }.disabled(model.fileOperation != nil)
            }
        }
        if recordings.isEmpty { ContentUnavailableView("No matching recordings", systemImage: "tray", description: Text("Record a session or import a raw capture using the toolbar.")) }
        else {
            Panel(title: "\(recordings.count) recordings") {
                ForEach(recordings) { info in
                    HStack(spacing: 12) {
                        Image(systemName: info.corrupt ? "exclamationmark.triangle" : info.complete ? "waveform" : "clock.badge.exclamationmark").foregroundStyle(info.corrupt ? .orange : .teal)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(info.name).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                            Text("\(info.sampleCount.formatted()) samples · \(info.corrupt ? "Invalid recording" : info.complete ? "Finalized" : "Incomplete")").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(model.selectedRecording == info.url ? "Selected" : "Review") { model.replay(info) }
                            .disabled(info.corrupt || model.ready || model.recording || model.fileOperation != nil)
                        Button { export(info) } label: { Image(systemName: "square.and.arrow.up") }.help("Export recording as ADC CSV").accessibilityLabel("Export \(info.name) as CSV")
                            .disabled(info.corrupt || model.ready || model.recording || model.fileOperation != nil)
                    }.padding(10).background(model.selectedRecording == info.url ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    if info.id != recordings.last?.id { Divider() }
                }
            }
        }
        #if !os(macOS)
        if let shareURL = shareURL { ShareLink(item: shareURL) { Label("Share exported CSV", systemImage: "square.and.arrow.up") } }
        #endif
        if let info = model.recordings.first(where: { $0.url == model.selectedRecording }), model.playback {
            WaveformWorkbench(samples: model.samples, title: "Recording review", onSelectionChange: { signalSelection = $0 })
                .id("\(info.url.absoluteString):\(model.replayOffset)")
            IntervalAnalysisView(selection: signalSelection)
            HStack {
                Button { model.replay(info, offset: max(0, model.replayOffset - 1280)) } label: { Label("Previous page", systemImage: "chevron.left") }.labelStyle(.iconOnly).help("Previous page").disabled(model.replayOffset == 0 || model.fileOperation != nil)
                Spacer()
                Text("Samples \(model.replayOffset + (model.samples.isEmpty ? 0 : 1))–\(model.replayOffset + model.samples.count) of \(info.sampleCount.formatted())").font(.caption.monospacedDigit())
                Spacer()
                Button { model.replay(info, offset: model.replayOffset + 1280) } label: { Label("Next page", systemImage: "chevron.right") }.labelStyle(.iconOnly).help("Next page").disabled(model.replayOffset + model.samples.count >= info.sampleCount || model.fileOperation != nil)
            }
        }
    }
    private func export(_ info: EEGRecordingInfo) {
        #if os(macOS)
        let panel = NSSavePanel(); panel.allowedContentTypes = [.commaSeparatedText]; panel.nameFieldStringValue = info.url.deletingPathExtension().lastPathComponent + ".csv"
        if panel.runModal() == .OK, let url = panel.url { model.export(info, to: url) }
        #else
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        model.export(info, to: url) { succeeded in if succeeded { shareURL = url } }
        #endif
    }
}

struct SignalInspector: View {
    @EnvironmentObject var model: AcquisitionModel
    var body: some View {
        Form {
            Section("Source") {
                LabeledContent("Mode", value: model.playback ? "Recorded" : "Live")
                LabeledContent("Samples", value: model.sampleCount.formatted())
                LabeledContent("Transport", value: model.transportStable ? "Stable" : "Not verified")
                if let sample = model.samples.last {
                    LabeledContent("Latest counter", value: String(sample.counter))
                    LabeledContent("Receipt time", value: sample.receivedAt.formatted(.number.precision(.fractionLength(3))) + " s")
                    LabeledContent("Calibration", value: sample.electrodesMicrovolts == nil ? "ADC only" : "µV conversion")
                }
            }
            Section("Raw sensor contact") {
                if model.playback {
                    Text("Contact snapshots are not loaded for this recording.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(AcquisitionModel.channels, id: \.self) { channel in LabeledContent(channel, value: model.contactRaw[channel].map(String.init) ?? "—") }
                }
                Text("Raw observations only; these are not validated good/poor contact scores.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Recent events") {
                if model.events.isEmpty { Text("No events yet").foregroundStyle(.secondary) }
                ForEach(Array(model.events.suffix(12).reversed().enumerated()), id: \.offset) { _, event in Text(event).font(.caption.monospaced()).textSelection(.enabled) }
            }
        }.formStyle(.grouped).navigationTitle("Inspector")
    }
}
struct CalibrationView: View {
    @EnvironmentObject var model: AcquisitionModel
    @State private var profile: EEGMentalProfile?
    @State private var datasetManifest: Data?
    @State private var datasetName = ""
    var body: some View {
        PageTitle(title: "Calibration", detail: "Define a task, record labeled trials and evaluate a separate session before any command output.")
        Panel(title: "Current boundary") {
            Label("Command output disabled", systemImage: "hand.raised").font(.headline)
            Text("This workspace trains experimental profiles from labeled recordings. It does not yet provide a physiologically validated intent classifier. Offline processing settings define the research recipe; they do not establish accuracy.").foregroundStyle(.secondary)
        }
        TrialCaptureView(model: model, cues: model.trialCues)
        DatasetBuilderView(manifest: $datasetManifest, manifestName: $datasetName)
        DatasetTrainingView(onSaved: { profile = $0 }, manifest: $datasetManifest, manifestName: $datasetName)
        ProfileInspectionView(profile: $profile, preparedManifest: datasetManifest)
        Panel(title: "Research sequence") {
            ForEach(Array(["Prepare sensors and verify transport", "Record neutral and intentional task trials", "Evaluate held-out sessions and artifact challenges", "Qualify a confirmation and cancel mechanism"].enumerated()), id: \.offset) { index, label in
                HStack(alignment: .top, spacing: 14) { Text(String(index + 1)).font(.callout.monospacedDigit()).foregroundStyle(.secondary); Text(label) }
            }
        }
    }
}
struct SystemView: View {
    @EnvironmentObject var model: AcquisitionModel
    var body: some View {
        Panel(title: "Data and runtime") {
            LabeledContent("Processing", value: "On device")
            LabeledContent("Storage", value: "Raw notifications + native sample events")
            LabeledContent("Cloud uploads", value: "None")
            LabeledContent("Qualification", value: "Research build")
            Text(model.directory.path).font(.caption.monospaced()).textSelection(.enabled)
        }
        Panel(title: "Recording writer") {
            if let stats=model.writerStatistics {
                LabeledContent("Recording generation",value:String(stats.generation))
                LabeledContent("Pending inputs",value:String(stats.pendingInputs))
                LabeledContent("Pending logical bytes",value:String(stats.pendingPayloadBytes))
                LabeledContent("Peak pending inputs",value:String(stats.peakPendingInputs))
                LabeledContent("Written / admitted inputs",value:"\(stats.writtenInputs) / \(stats.admittedInputs)")
                LabeledContent("Discarded inputs",value:String(stats.discardedInputs))
                LabeledContent("Failed writes",value:String(stats.failedWrites))
                LabeledContent("Maximum queue wait",value:stats.writtenInputs+stats.failedWrites>0 ? String(format:"%.3f ms",stats.maximumQueueWaitSeconds*1000) : "No writes observed")
                LabeledContent("Maximum write duration",value:stats.writtenInputs+stats.failedWrites>0 ? String(format:"%.3f ms",stats.maximumWriteSeconds*1000) : "No writes observed")
                if stats.failed {Text("Writer failed; capture is incomplete.").foregroundStyle(.red)}
                if stats.cleanupPending {Text("Closing incomplete recording. Restart is unavailable until storage cleanup finishes.").foregroundStyle(.orange)}
            }
            Text("Per-recording asynchronous input measurements. Logical bytes are not process memory. Control barriers and filesystem synchronization are excluded; these values do not establish end-to-end signal latency.").font(.caption).foregroundStyle(.secondary)
        }
        Panel(title: "Qualification remaining") { Text("Physical Apple-device acquisition, long-duration durability, radio interruptions, signed distribution and validated physiological interpretation remain release gates. Decoder parity against archived captures does not replace these checks.").foregroundStyle(.secondary) }
        Panel(title: "Session events") {
            if model.events.isEmpty { ContentUnavailableView("No events", systemImage: "list.bullet.rectangle") }
            ForEach(Array(model.events.enumerated()), id: \.offset) { _, event in Text(event).font(.caption.monospaced()).textSelection(.enabled) }
        }
    }
}
