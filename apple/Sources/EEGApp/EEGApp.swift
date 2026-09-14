import SwiftUI
import EEGCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

@main
struct EEGApplication: App {
    @StateObject private var model=AcquisitionModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup("EEG") { WorkspaceView().environmentObject(model).onOpenURL {model.importRawCapture($0)}
            #if os(macOS)
            .frame(minWidth:720,minHeight:560)
            .onReceive(NotificationCenter.default.publisher(for:NSApplication.willTerminateNotification)) { _ in model.prepareForTermination() }
            #else
            .onChange(of:scenePhase) { _,phase in if phase == .background {model.prepareForTermination()} }
            #endif
        }
        #if os(macOS)
        .defaultSize(width:1240,height:820)
        #endif
    }
}

enum Workspace: String, CaseIterable, Identifiable {
    case live="Live signals", recordings="Recordings", analysis="Analysis", calibration="Calibration", system="System"
    var id:String { rawValue }
    var icon:String { switch self { case .live:return "waveform.path.ecg";case .recordings:return "tray.full";case .analysis:return "chart.xyaxis.line";case .calibration:return "scope";case .system:return "checkmark.shield" } }
}
struct WorkspaceView: View {
    @EnvironmentObject var model:AcquisitionModel
    @State private var selection:Workspace? = .live
    var body: some View {
        NavigationSplitView {
            VStack(alignment:.leading,spacing:24) {
                HStack(spacing:10) { Image(systemName:"waveform.path.ecg").font(.title).foregroundStyle(.teal);VStack(alignment:.leading) { Text("EEG").font(.title2.bold());Text("Your signal. Your workspace.").font(.caption).foregroundStyle(.secondary) } }.padding(.horizontal,16).padding(.top,24)
                List(Workspace.allCases,selection:$selection) { item in Label(item.rawValue,systemImage:item.icon).padding(.vertical,6).tag(item) }.listStyle(.sidebar)
                VStack(alignment:.leading,spacing:8) { Label("On-device processing",systemImage:"lock.shield").font(.caption.weight(.medium));Text("Native research preview\nNo account · No cloud upload").font(.caption2).foregroundStyle(.secondary) }.padding(18)
            }.navigationSplitViewColumnWidth(min:200,ideal:230,max:270)
        } detail: {
            VStack(spacing:0) {
                HStack { Label(model.phase,systemImage:model.ready ? "dot.radiowaves.left.and.right":"circle.dotted").font(.callout.weight(.medium));Spacer();if model.recording { Label("Recording",systemImage:"record.circle.fill").foregroundStyle(.red) };Text(model.playback ? "REPLAY":"LOCAL").font(.caption.monospaced().bold()).padding(7).background(.teal.opacity(0.12),in:Capsule()) }.padding(20)
                Divider()
                ScrollView { VStack(alignment:.leading,spacing:22) {
                    switch selection ?? .live {
                    case .live:LiveView()
                    case .recordings:LibraryView()
                    case .analysis:AnalysisView()
                    case .calibration:CalibrationView()
                    case .system:SystemView()
                    }
                }.padding(28).frame(maxWidth:1250,alignment:.leading).frame(maxWidth:.infinity) }
            }.navigationTitle((selection ?? .live).rawValue)
        }
        .onChange(of:model.playback) { _,value in if value {selection = .recordings} }
        .alert("EEG",isPresented:Binding(get:{model.message != nil},set:{if !$0 {model.message=nil}})) { Button("OK") { model.message=nil } } message: { Text(model.message ?? "") }
    }
}
struct Panel<Content:View>: View {
    let title:String
    @ViewBuilder var content:Content
    var body:some View { VStack(alignment:.leading,spacing:16) { Text(title).font(.headline);content }.padding(20).frame(maxWidth:.infinity,alignment:.leading).background(.quaternary.opacity(0.35),in:RoundedRectangle(cornerRadius:18)).overlay(RoundedRectangle(cornerRadius:18).stroke(.primary.opacity(0.07))) }
}
struct PageTitle:View {
    let title:String;let detail:String
    var body:some View { VStack(alignment:.leading,spacing:7) { Text(title).font(.largeTitle.bold());Text(detail).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) } }
}
struct LiveView:View {
    @EnvironmentObject var model:AcquisitionModel
    @State private var marker=""
    var body:some View {
        PageTitle(title:"A clear view of your signal",detail:"Connect your headset, inspect the channels and record directly to your device.")
        Panel(title:"Headset") {
            HStack { Label(model.ready ? "EPOC X connected":"EPOC X",systemImage:"sensor.tag.radiowaves.forward");Spacer();Button(model.scanning ? "Scanning…":"Find headset") { model.scan() }.disabled(model.scanning || model.ready);if model.ready { Button("Disconnect") { model.disconnect() } } }
            if !model.devices.isEmpty && !model.ready { ForEach(model.devices) { device in HStack { VStack(alignment:.leading) { Text(device.name);Text(device.id.uuidString).font(.caption.monospaced()).foregroundStyle(.secondary) };Spacer();Button("Connect") { model.connect(device) }.buttonStyle(.borderedProminent).tint(.teal) } } }
            if model.devices.isEmpty && !model.ready { Text("Power on the headset nearby. Bluetooth permission is requested by macOS, iOS or visionOS.").font(.callout).foregroundStyle(.secondary) }
        }
        HStack(spacing:16) { Metric(title:model.playback ? "Recorded samples":"Samples received",value:model.sampleCount.formatted());Metric(title:"Transport",value:model.playback ? "Replay":(model.transportStable ? "Stable":"Not stable"));Metric(title:model.playback ? "Page samples":"Decode errors",value:model.playback ? model.samples.count.formatted():model.decodeErrors.formatted()) }
        Panel(title:model.playback ? "Recorded waveforms":"Live waveforms") {
            WaveformView(samples:model.samples).frame(height:340)
            Text("Display centered per channel · stored ADC values are unchanged · gaps break the trace").font(.caption).foregroundStyle(.secondary)
        }
        Panel(title:"Recording") {
            HStack { VStack(alignment:.leading,spacing:4) { Text(model.recording ? "Capturing raw notifications and EEG":"Ready when you are").font(.headline);Text("Local files. No subscription or time quota. Available storage and battery apply.").font(.caption).foregroundStyle(.secondary) };Spacer();Button(model.recording ? "Stop recording":"Start recording") { if model.recording {model.stopRecording()} else {model.startRecording()} }.buttonStyle(.borderedProminent).tint(model.recording ? .red:.teal).disabled(!model.ready || model.playback) }
            HStack { TextField("Add an event marker…",text:$marker).textFieldStyle(.roundedBorder);Button("Mark") { model.annotate(marker);marker="" }.disabled(!model.recording || marker.isEmpty) }
        }
        Panel(title:"Sensor contact · raw observations") {
            LazyVGrid(columns:[GridItem(.adaptive(minimum:90))],spacing:12) { ForEach(AcquisitionModel.channels,id:\.self) { ch in VStack(spacing:7) { Text(ch).font(.caption.bold());Text(model.contactRaw[ch].map{String($0)} ?? "—").font(.body.monospacedDigit()) }.frame(maxWidth:.infinity).padding(12).background(.teal.opacity(0.07),in:RoundedRectangle(cornerRadius:10)) } }
            Text("Raw contact values only. Good/poor contact classes have not yet been validated.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
struct Metric:View { let title:String;let value:String;var body:some View { VStack(alignment:.leading,spacing:8) { Text(title).font(.caption).foregroundStyle(.secondary);Text(value).font(.title2.weight(.semibold).monospacedDigit()) }.frame(maxWidth:.infinity,alignment:.leading).padding(18).background(.quaternary.opacity(0.25),in:RoundedRectangle(cornerRadius:14)) } }
struct WaveformView:View {
    let samples:[EEGSample]
    var body:some View {
        if samples.isEmpty { ContentUnavailableView("Waiting for signal",systemImage:"waveform.path",description:Text("Live or recorded samples appear here. No simulated data is shown.")) }
        else { Canvas { context,size in
            let channels=AcquisitionModel.channels
            for (row,ch) in channels.enumerated() {
                let y=CGFloat(row+1)*size.height/CGFloat(channels.count+1)
                context.draw(Text(ch).font(.system(size:10,weight:.medium,design:.monospaced)).foregroundColor(.secondary),at:CGPoint(x:18,y:y))
                let values=samples.compactMap{$0.electrodesADC[ch]};guard !values.isEmpty else {continue};let mean=values.reduce(0,+)/Double(values.count)
                let extent=max(40,values.map{abs($0-mean)}.max() ?? 40);var path=Path();var begun=false
                for (i,s) in samples.enumerated() {
                    guard let value=s.electrodesADC[ch] else {begun=false;continue}
                    let p=CGPoint(x:43+CGFloat(i)/CGFloat(max(1,samples.count-1))*(size.width-48),y:y-CGFloat((value-mean)/extent)*size.height/CGFloat(channels.count+1)*0.42)
                    if !begun || !s.continuous {path.move(to:p);begun=true} else {path.addLine(to:p)}
                }
                context.stroke(path,with:.color(.teal),lineWidth:1)
            }
        }.accessibilityLabel("Fourteen EEG channel traces. Each channel is centered and independently scaled for display.") }
    }
}
struct LibraryView:View {
    @EnvironmentObject var model:AcquisitionModel
    @State private var showingImporter=false
    #if !os(macOS)
    @State private var shareURL:URL?
    #endif
    var body:some View {
        PageTitle(title:"Your recording library",detail:"Every session keeps raw notifications, decoded samples and your event markers together.")
        HStack { Text("\(model.recordings.count) recordings").foregroundStyle(.secondary);Spacer();Button("Import raw capture") {showingImporter=true}.disabled(model.ready || model.recording);Button("Refresh") {model.refreshRecordings()} }
            .fileImporter(isPresented:$showingImporter,allowedContentTypes:[.json],allowsMultipleSelection:false) { result in
                do { if let url=try result.get().first { model.importRawCapture(url) } } catch { model.message=error.localizedDescription }
            }
        #if !os(macOS)
        if let shareURL=shareURL { ShareLink(item:shareURL) {Label("Share exported CSV",systemImage:"square.and.arrow.up")} }
        #endif
        if model.recordings.isEmpty { ContentUnavailableView("No recordings yet",systemImage:"tray",description:Text("Record from Live signals. Files stay in this app’s local storage.")) }
        ForEach(model.recordings) { info in Panel(title:info.name) {
            HStack { Label(info.corrupt ? "Corrupt":(info.complete ? "Finalized":"Incomplete"),systemImage:info.complete ? "checkmark.circle":"exclamationmark.circle");Text("\(info.sampleCount.formatted()) samples").foregroundStyle(.secondary);Spacer();Button("Review") {model.replay(info)};Button("Export CSV") { export(info) } }
            if model.selectedRecording==info.url { WaveformView(samples:model.samples).frame(height:300);HStack { Button("Previous") {model.replay(info,offset:max(0,model.replayOffset-1280))}.disabled(model.replayOffset==0);Text("Samples \(model.replayOffset)–\(model.replayOffset+model.samples.count)").font(.caption.monospaced());Button("Next") {model.replay(info,offset:model.replayOffset+1280)}.disabled(model.replayOffset+model.samples.count>=info.sampleCount) } }
        } }
    }
    private func export(_ info:EEGRecordingInfo) {
        #if os(macOS)
        let panel=NSSavePanel();panel.allowedContentTypes=[.commaSeparatedText];panel.nameFieldStringValue=info.url.deletingPathExtension().lastPathComponent+".csv";panel.canCreateDirectories=true
        if panel.runModal() == .OK,let url=panel.url { model.export(info,to:url) }
        #else
        // Export to a new local file; expose it using the system share sheet below.
        let destination=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".csv");if model.export(info,to:destination) {shareURL=destination}
        #endif
    }
}
struct AnalysisView:View {
    @EnvironmentObject var model:AcquisitionModel
    var body:some View {
        PageTitle(title:"Analysis with a clear provenance",detail:"Recorded samples remain the source. Every derived measure needs an explicit method and validation.")
        Panel(title:"Available now") { Label("Channel waveforms and raw ADC inspection",systemImage:"checkmark.circle");Label("Channel ADC values exported as CSV",systemImage:"checkmark.circle");Text("Open a recording to review its samples. The repository also includes reproducible Python comparison and signal-analysis tools.").foregroundStyle(.secondary) }
        Panel(title:"Next scientific modules") { Text("Spectrum and band power · artifact labeling · experiment segmentation · synchronized research streams").font(.headline);Text("These native modules are not enabled yet. Stress, attention and emotional-state scores are not inferred from raw waveforms.").foregroundStyle(.secondary) }
    }
}
struct CalibrationView:View {
    var body:some View {
        PageTitle(title:"Control begins with calibration",detail:"A reliable interface needs an intentional command, a neutral state and a way to cancel.")
        Panel(title:"Command training · not enabled") { Text("User profiles → labeled trials → held-out evaluation → confirmation → command output").font(.headline);Text("Raw EEG decoding is verified against recorded reference samples. Intent classification is a separate research milestone. No EEG sample currently triggers an action.").foregroundStyle(.secondary) }
        Panel(title:"Apple accessibility") { Label("BCI / HID integration planned",systemImage:"accessibility");Text("Apple’s BCI HID reference describes interpreted device reports. A native app alone does not establish permission to emulate a system input device. Hardware and platform integration must be tested separately.").foregroundStyle(.secondary) }
    }
}
struct SystemView:View {
    @EnvironmentObject var model:AcquisitionModel
    var body:some View {
        PageTitle(title:"Built around your data",detail:"One native application. Independent acquisition. Explicit scientific limits.")
        Panel(title:"Workspace") { LabeledContent("Processing",value:"On device");LabeledContent("Account",value:"Not required");LabeledContent("Cloud upload",value:"None");LabeledContent("Release status",value:"Research preview");Text(model.directory.path).font(.caption.monospaced()).textSelection(.enabled) }
        Panel(title:"Qualification remaining") { Text("Standalone hardware startup · extended soak · sleep/wake and radio interruptions · validated contact classes · signed distribution · physical iOS and visionOS testing").foregroundStyle(.secondary) }
        Panel(title:"Session events") { if model.events.isEmpty { Text("No events yet").foregroundStyle(.secondary) };ForEach(Array(model.events.enumerated()),id:\.offset) { _,event in Text(event).font(.caption.monospaced()).textSelection(.enabled) } }
    }
}
