import SwiftUI
import CoreBluetooth
import EEGCore

final class AcquisitionModel: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    struct Device: Identifiable { let id: UUID; let name: String; let peripheral: CBPeripheral }
    @Published var devices: [Device] = []
    @Published var phase = "Disconnected"
    @Published var message: String?
    @Published var samples: [EEGSample] = []
    @Published private(set) var trialPlan: EEGTrialPlan?
    @Published private(set) var trialsStarted = 0
    lazy var trialCues = TrialCueController(acquisition: self)
    @Published private(set) var trial: EEGTrialEvidence?
    private var trialSession: EEGTrialSession?
    @Published private(set) var shadowActive = false
    @Published private(set) var shadowStatus = "Stopped"
    @Published private(set) var shadowResult: EEGWindowInferenceResult?
    private var shadow: EEGLiveInference?
    private var shadowToken = UUID()
    @Published var recording = false
    @Published var sampleCount = 0
    @Published var decodeErrors = 0
    @Published var transportStable = false
    @Published var contactRaw: [String: UInt16] = [:]
    @Published var recordings: [EEGRecordingInfo] = []
    @Published var events: [String] = []
    @Published var playback = false
    @Published var selectedRecording: URL?
    @Published var replayOffset = 0
    @Published var ready = false
    @Published var scanning = false
    @Published var fileOperation:String?
    private let fileQueue=DispatchQueue(label:"cloud.autonomy.eeg.files",qos:.userInitiated)
    private var libraryRequest=0
    let directory: URL
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var decoder: EEGDecoder?
    private var metadata: [String: Data] = [:]
    private var pendingMetadata = Set<String>()
    private var dataCharacteristic: CBCharacteristic?
    private var store: EEGRecordingStore?
    private var scanTimer: Timer?
    private var freshnessTimer: Timer?
    private var connectionTimer: Timer?
    private var configuring = false
    private var lastPreviewUpdate = 0.0
    private var previewBuffer: [EEGSample] = []
    private var lastArrival: TimeInterval?
    private var stableSince: TimeInterval?
    private var contiguous = 0
    private var origin = ProcessInfo.processInfo.systemUptime
    private let service = CBUUID(string:"81072f40-9f3d-11e3-a9dc-0002a5d5c51b")
    private let dataID = "81072F41-9F3D-11E3-A9DC-0002A5D5C51B"
    private let serialID = "2A25"
    private let revisionID = "2A28"
    private let configID = "81072F44-9F3D-11E3-A9DC-0002A5D5C51B"
    static let channels = ["AF3","F7","F3","FC5","T7","P7","O1","O2","P8","T8","FC6","F4","F8","AF4"]
    override init() {
        directory = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("EEG/Recordings",isDirectory:true)
        super.init()
        do { store = try EEGRecordingStore(directory:directory); refreshRecordings() } catch { message=error.localizedDescription }
        // Bluetooth is initialized only when the user chooses Find headset.
        freshnessTimer=Timer.scheduledTimer(withTimeInterval:0.25,repeats:true) { [weak self] _ in
            guard let self=self, let last=self.lastArrival, self.ready else { return }
            if ProcessInfo.processInfo.systemUptime-last>0.5 {
                self.setTransport(false,reason:"stale_input");self.stableSince=nil;self.contiguous=0
                if self.phase != "Signal stale" { self.phase="Signal stale";self.event("No recent samples; transport stability reset") }
                if ProcessInfo.processInfo.systemUptime-last > 5 { self.message="No EEG notifications for five seconds. Reconnect the headset to retry.";self.disconnect() }
            }
        }
    }
    func centralManagerDidUpdateState(_ central:CBCentralManager) {
        switch central.state {
        case .poweredOn:phase="Ready to scan";if scanning { beginScan() }
        case .unauthorized:scanning=false;phase="Bluetooth permission required";message="Allow EEG to use Bluetooth in System Settings → Privacy & Security."
        case .poweredOff:disconnect();phase="Bluetooth off";scanning=false
        case .unsupported:phase="Bluetooth unavailable"
        default:phase="Checking Bluetooth"
        }
    }
    func scan() {
        guard peripheral == nil,fileOperation==nil else { return }
        if central == nil { scanning=true;central=CBCentralManager(delegate:self,queue:.main);return }
        beginScan()
    }
    private func beginScan() {
        guard central.state == .poweredOn, peripheral == nil else { scanning=false;return }
        playback=false;scanning=true;devices=[];phase="Scanning nearby headsets"
        for p in central.retrieveConnectedPeripherals(withServices:[service]) { add(p) }
        central.scanForPeripherals(withServices:[service],options:[CBCentralManagerScanOptionAllowDuplicatesKey:false])
        scanTimer?.invalidate();scanTimer=Timer.scheduledTimer(withTimeInterval:8,repeats:false) { [weak self] _ in
            self?.central.stopScan();self?.scanning=false;self?.phase="Select a headset"
        }
    }
    private func add(_ p:CBPeripheral) {
        if !devices.contains(where:{$0.id==p.identifier}) { devices.append(Device(id:p.identifier,name:p.name ?? "EPOC X",peripheral:p)) }
    }
    func centralManager(_ central:CBCentralManager,didDiscover peripheral:CBPeripheral,advertisementData:[String:Any],rssi RSSI:NSNumber) { add(peripheral) }
    func connect(_ device:Device) {
        guard peripheral == nil,central != nil,fileOperation==nil else { return }
        central.stopScan();scanTimer?.invalidate();scanning=false;playback=false;samples=[];sampleCount=0;decodeErrors=0;contactRaw=[:];metadata=[:];pendingMetadata=[];dataCharacteristic=nil;decoder=nil;configuring=false;ready=false;previewBuffer=[];transportStable=false;lastArrival=nil;stableSince=nil;contiguous=0;origin=ProcessInfo.processInfo.systemUptime
        peripheral=device.peripheral;device.peripheral.delegate=self;phase="Connecting to \(device.name)";central.connect(device.peripheral);startDeadline(seconds:15,message:"Headset connection timed out.")
    }
    func centralManager(_ central:CBCentralManager,didConnect peripheral:CBPeripheral) { startDeadline(seconds:10,message:"Device metadata timed out. Disconnect other readers and reconnect.");phase="Reading device configuration";peripheral.discoverServices([service,CBUUID(string:"180A")]) }
    func centralManager(_ central:CBCentralManager,didFailToConnect peripheral:CBPeripheral,error:Error?) { connectionTimer?.invalidate();self.peripheral=nil;phase="Connection failed";message=error?.localizedDescription }
    func centralManager(_ central:CBCentralManager,didDisconnectPeripheral peripheral:CBPeripheral,error:Error?) {
        connectionTimer?.invalidate();configuring=false;
        event("Disconnected"+(error.map{": "+$0.localizedDescription} ?? ""));setTransport(false,reason:"disconnected");if recording { stopRecording() };self.peripheral=nil;ready=false;transportStable=false;phase="Disconnected"
    }
    func peripheral(_ peripheral:CBPeripheral,didDiscoverServices error:Error?) {
        if let error=error { fail(error);return }
        guard let services=peripheral.services else { return }
        pendingMetadata=Set([serialID,revisionID,configID])
        for s in services { peripheral.discoverCharacteristics(nil,for:s) }
    }
    func peripheral(_ peripheral:CBPeripheral,didDiscoverCharacteristicsFor service:CBService,error:Error?) {
        if let error=error { fail(error);return }
        for c in service.characteristics ?? [] {
            let key=c.uuid.uuidString.uppercased()
            if key==dataID { dataCharacteristic=c }
            if pendingMetadata.contains(key) { peripheral.readValue(for:c) }
        }
        configureIfPossible()
    }
    private func configureIfPossible() {
        guard !ready,!configuring,let serial=metadata[serialID],let revision=metadata[revisionID],!pendingMetadata.contains(configID),let c=dataCharacteristic else { return }
        do {
            decoder=try EEGDecoder(serial:serial,revision:revision,configuration:metadata[configID]);configuring=true;startDeadline(seconds:8,message:"Headset notifications did not start.");peripheral?.setNotifyValue(true,for:c);phase="Starting signal stream"
        } catch { fail(error) }
    }
    func peripheral(_ peripheral:CBPeripheral,didUpdateNotificationStateFor characteristic:CBCharacteristic,error:Error?) {
        if let error=error { fail(error);return };guard characteristic.uuid.uuidString.uppercased()==dataID else { return };connectionTimer?.invalidate();ready=characteristic.isNotifying;lastArrival=ProcessInfo.processInfo.systemUptime;phase=ready ? "Listening · stabilizing":"Notifications stopped"
    }
    func peripheral(_ peripheral:CBPeripheral,didUpdateValueFor characteristic:CBCharacteristic,error:Error?) {
        let key=characteristic.uuid.uuidString.uppercased()
        if key != dataID {
            pendingMetadata.remove(key)
            if let value=characteristic.value,error==nil { metadata[key]=value }
            else if key != configID { if let error=error { fail(error) };return }
            configureIfPossible();return
        }
        if let error=error { fail(error);return };guard let data=characteristic.value,decoder != nil else { return }
        let now=ProcessInfo.processInfo.systemUptime
        do {
            if recording { try store?.appendEvent(kind:"ble_notification",fields:["hex":data.map{String(format:"%02x",$0)}.joined(),"receivedAt":String(now-origin)]) }
        } catch { storageFailed(error);return }
        let decoded:[EEGSample]
        do { decoded=try decoder!.decode(packet:data,receivedAt:now-origin) }
        catch {
            decodeErrors+=1;setTransport(false,reason:"rejected_packet",receivedAt:now-origin);stableSince=nil;contiguous=0;lastArrival=now
            event("Rejected packet: "+error.localizedDescription)
            do { if recording { try store?.appendEvent(kind:"decode_error",fields:["message":error.localizedDescription,"receivedAt":String(now-origin)]) } }
            catch { storageFailed(error) }
            return
        }
        let gap=lastArrival.map{now-$0>0.5} ?? false
        if gap || decoded.contains(where:{!$0.continuous}) { stableSince=nil;contiguous=0;setTransport(false,reason:gap ? "arrival_gap":"counter_discontinuity",receivedAt:now-origin) }
        else if stableSince==nil { stableSince=now }
        else { contiguous+=decoded.count;setTransport(contiguous>=256 && now-(stableSince ?? now)>=2,reason:"contiguous_sample_counters",receivedAt:now-origin) }
        lastArrival=now;sampleCount+=decoded.count;phase=transportStable ? "Live · transport stable":"Live · stabilizing"
        previewBuffer.append(contentsOf:decoded)
        if previewBuffer.count>1280 { previewBuffer.removeFirst(previewBuffer.count-1280) }
        if now-lastPreviewUpdate >= 0.1,!playback { samples=previewBuffer;lastPreviewUpdate=now }
        do {
            for sample in decoded {
                if recording { try store?.append(sample:sample) }
                if let shadow,!shadow.submit(.sample(sample)) { stopShadow(reason:"inference_overload") }
                let slot=Int(sample.counter)%64
                if metadata[configID]==Data([1,128,0,16,32,16]),slot<14,sample.adcWords.count==15 { contactRaw[Self.channels[slot]]=sample.adcWords[7] }
            }
        } catch { storageFailed(error) }
    }
    private func recordTransport(reason:String,receivedAt:Double?=nil) throws {
        try store?.appendEvent(kind:"transport_status",fields:["status":transportStable ? "stable":"recovering",
            "reason":reason,"receivedAt":String(receivedAt ?? (ProcessInfo.processInfo.systemUptime-origin)),
            "calibrated":String(decoder?.voltageDivisor != nil),"physiology_validated":"false"])
    }
    private func setTransport(_ stable:Bool,reason:String,receivedAt:Double?=nil) {
        let changed=transportStable != stable
        transportStable=stable
        if !stable { stopShadow(reason:reason);interruptTrial(reason: reason) }
        guard changed,recording else {return}
        do {try recordTransport(reason:reason,receivedAt:receivedAt)} catch {storageFailed(error)}
    }
    /// Called on orderly lifecycle shutdown. Forced kill leaves the file incomplete.
    func prepareForTermination() {disconnect()}
    private func startDeadline(seconds:Double,message:String) {
        connectionTimer?.invalidate()
        connectionTimer=Timer.scheduledTimer(withTimeInterval:seconds,repeats:false) { [weak self] _ in
            self?.message=message;self?.event(message);self?.disconnect()
        }
    }
    private func storageFailed(_ error:Error) {
        stopShadow(reason:"recording_storage_failed",persist:false)
        event("Recording storage failed: "+error.localizedDescription)
        interruptTrial(reason: "recording_storage_failed")
        store?.abort();recording=false;refreshRecordings()
        message="Recording aborted after a storage failure: "+error.localizedDescription
    }
    private func fail(_ error:Error) { message=error.localizedDescription;event(error.localizedDescription);disconnect() }
    func disconnect() { connectionTimer?.invalidate();scanTimer?.invalidate();central?.stopScan();scanning=false;configuring=false;setTransport(false,reason:"disconnect_requested");if recording { stopRecording() };if let p=peripheral { central?.cancelPeripheralConnection(p) };ready=false;transportStable=false }
    func startRecording() {
        guard ready,!recording,!playback,fileOperation==nil,let store=store else { return }
        do {
            let url=try store.start();recording=true
            trial=nil;trialPlan=nil;trialsStarted=0;trialSession=EEGTrialSession { try store.appendTrialEvidence($0) }
            try store.appendEvent(kind:"device_metadata",fields:metadata.mapValues{$0.map{String(format:"%02x",$0)}.joined()})
            try recordTransport(reason:"recording_start")
            event("Recording started: "+url.lastPathComponent)
        } catch { storageFailed(error) }
    }
    func stopRecording() {
        guard recording else { return }
        stopShadow(reason:"recording_stopped")
        interruptTrial(reason: "recording_stopped")
        guard recording else { return }
        do { try store?.appendEvent(kind:"transport_checkpoint",fields:["stable":String(transportStable),"decode_errors":String(decodeErrors),"receivedAt":String(ProcessInfo.processInfo.systemUptime-origin)]) } catch { storageFailed(error);return }
        do { try store?.finish() } catch { message=error.localizedDescription }
        recording=false;refreshRecordings();event("Recording stopped")
    }
    /// Uses exactly the receipt clock used by the decoder, not wall-clock time.
    var recordingClock: Double { ProcessInfo.processInfo.systemUptime-origin }
    func commitTrialPlan(participantID: String, sessionID: String) throws {
        guard recording,trialPlan == nil,trial == nil,let store else { throw EEGTrialEvidence.Failure.invalidTransition }
        let plan = try EEGTrialPlan(sessionID: sessionID,participantID: participantID,seed: UInt64.random(in: .min ... .max))
        let json = String(decoding: try JSONEncoder().encode(plan),as: UTF8.self)
        do {
            try store.appendEvent(kind: "trial_plan",fields: ["json":json,"receivedAt":String(recordingClock)])
            trialPlan=plan
        } catch { storageFailed(error);throw error }
    }
    func nextPlannedTrial() throws -> EEGTrialEvidence {
        guard let trialPlan else { throw EEGTrialEvidence.Failure.invalidTransition }
        do { return try trialPlan.next(after:trial,started:trialsStarted,at:recordingClock) }
        catch EEGTrialEvidence.Failure.readinessMissing {
            throw NSError(domain: "EEGTrialPlan",code:1,userInfo:[NSLocalizedDescriptionKey:"Rest before the next trial: at least 10 seconds after review or interruption, or 60 seconds after each block of eight."])
        }
    }
    func beginTrial(_ planned: EEGTrialEvidence) throws {
        guard recording,ready,transportStable,!playback,let trialSession else { throw EEGTrialEvidence.Failure.readinessMissing }
        let expected = try nextPlannedTrial()
        guard planned.id == expected.id,planned.sessionID == expected.sessionID,
              planned.participantID == expected.participantID,planned.requestedCondition == expected.requestedCondition,
              planned.startingNumber == expected.startingNumber else { throw EEGTrialEvidence.Failure.invalidTransition }
        do { try trialSession.begin(planned);trial=trialSession.trial;trialsStarted+=1 }
        catch { if trialSession.persistenceFailure != nil { storageFailed(error) };throw error }
    }
    func transitionTrial(_ change: (inout EEGTrialEvidence, Double) throws -> Void) throws {
        guard recording,let trialSession else { throw EEGRecordingError.notRecording }
        do { try trialSession.transition(at: recordingClock,change);trial=trialSession.trial }
        catch { trial=trialSession.trial;if trialSession.persistenceFailure != nil { storageFailed(error) };throw error }
    }
    private func interruptTrial(reason: String) {
        guard let trialSession,trialSession.active else { return }
        do { try trialSession.interrupt(reason: reason,at: recordingClock) }
        catch {
            // Do not recurse through storageFailed: a failed interruption has
            // already invalidated the in-memory trial and may not be durable.
            store?.abort();recording=false;refreshRecordings()
            message="Trial evidence could not be saved: "+error.localizedDescription
        }
        trial=trialSession.trial
    }
    func startShadow(profile: EEGMentalProfile, sessionID: String, participantConfirmed: Bool) throws {
        guard participantConfirmed,recording,ready,transportStable,!playback,!shadowActive,let store else { throw EEGTrialEvidence.Failure.readinessMissing }
        guard !profile.trainingSessions.contains(sessionID) else { throw EEGReplayInference.Failure.trainingRecording }
        let token=UUID();shadowToken=token
        let consumer=try EEGLiveInference(profile:profile,participantID:profile.participantID,sessionID:sessionID) { [weak self] output in
            DispatchQueue.main.async {
                guard let self,self.shadowToken == token,self.shadowActive,
                      self.shadow?.generation == output.generation else { return }
                if let failure=output.failure { self.stopShadow(reason:failure);return }
                guard let row=output.window else { return }
                do {
                    try self.store?.appendEvent(kind:"shadow_inference",fields:["profile_id":profile.id,
                        "feature_config_id":EEGMentalFeatures.configurationID,"session_id":sessionID,
                        "ordinal":String(row.ordinal),"candidate":row.candidate ?? "",
                        "has_candidate":String(row.candidate != nil),"reasons":row.reasons.joined(separator:";"),
                        "status":row.status,"system_control_enabled":"false","receivedAt":String(self.recordingClock)])
                    self.shadowResult=row;self.shadowStatus="Experimental shadow result — no reliable command"
                } catch { self.storageFailed(error) }
            }
        }
        do {
            try store.appendEvent(kind:"shadow_start",fields:["profile_id":profile.id,"participant_id":profile.participantID,
                "session_id":sessionID,"feature_config_id":EEGMentalFeatures.configurationID,
                "system_control_enabled":"false","receivedAt":String(recordingClock)])
            let device=metadata.mapValues { $0.map { String(format:"%02x",$0) }.joined() }.merging(["kind":"device_metadata"]) { _,new in new }
            guard consumer.submit(.event(try JSONSerialization.data(withJSONObject:device))),
                  consumer.submit(.event(try JSONSerialization.data(withJSONObject:["kind":"transport_status","status":"stable"]))) else { throw EEGRecordingError.invalidData }
            shadow=consumer;shadowActive=true;shadowResult=nil;shadowStatus="Waiting for validated windows"
        } catch { consumer.stop();storageFailed(error);throw error }
    }
    func stopShadow(reason: String = "operator_stopped", persist: Bool = true) {
        guard shadow != nil else { return }
        shadow?.stop();shadow=nil;shadowToken=UUID();shadowActive=false;shadowResult=nil;shadowStatus="Stopped: "+reason
        if persist,recording {
            do { try store?.appendEvent(kind:"shadow_stop",fields:["reason":reason,"receivedAt":String(recordingClock)]) }
            catch { storageFailed(error) }
        }
    }
    func refreshRecordings() {
        libraryRequest+=1;let request=libraryRequest;let directory=self.directory
        fileQueue.async { [weak self] in
            let result=Result {try EEGRecordingStore(directory:directory).inventory()}
            DispatchQueue.main.async {
                guard let self=self,self.libraryRequest==request else {return}
                switch result {case .success(let items):self.recordings=items;case .failure(let error):self.message=error.localizedDescription}
            }
        }
    }
    func replay(_ info:EEGRecordingInfo,offset:Int=0) {
        guard !recording,peripheral==nil,fileOperation==nil else {message="Finish the current operation and disconnect before replay.";return}
        fileOperation="Loading waveform";let directory=self.directory
        fileQueue.async { [weak self] in
            let result=Result {try EEGRecordingStore(directory:directory).replay(recording:info.url,offset:offset,limit:1280)}
            DispatchQueue.main.async {
                guard let self=self else {return};self.fileOperation=nil
                switch result {
                case .success(let values):self.samples=values;self.selectedRecording=info.url;self.playback=true;self.sampleCount=info.sampleCount;self.replayOffset=offset;self.phase="Recorded data · replay"
                case .failure(let error):self.message=error.localizedDescription
                }
            }
        }
    }
    func export(_ info:EEGRecordingInfo,to destination:URL,completion:@escaping(Bool)->Void = {_ in}) {
        guard !recording,peripheral==nil,fileOperation==nil else {message="Finish the current operation and disconnect before exporting.";completion(false);return}
        fileOperation="Exporting CSV";let directory=self.directory
        fileQueue.async { [weak self] in
            let result=Result {try EEGRecordingStore(directory:directory).exportCSV(recording:info.url,to:destination)}
            DispatchQueue.main.async {
                guard let self=self else {return};self.fileOperation=nil
                switch result {
                case .success:self.event("Exported \(destination.lastPathComponent)");completion(true)
                case .failure(let error):self.message=error.localizedDescription;completion(false)
                }
            }
        }
    }
    func annotate(_ text:String) {
        guard recording,!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return }
        do { try store?.appendEvent(kind:"annotation",fields:["text":String(text.prefix(1000)),"receivedAt":String(ProcessInfo.processInfo.systemUptime-origin)]);event("Marker: "+text) } catch { storageFailed(error) }
    }
    /// Import work is isolated from main-thread interaction and Bluetooth callbacks.
    func importRawCapture(_ url:URL) {
        guard !recording,peripheral==nil,fileOperation==nil else {message="Finish the current operation and disconnect before importing.";return}
        guard url.isFileURL else {message="Import requires a local capture file.";return}
        fileOperation="Importing raw recording"
        let scoped=url.startAccessingSecurityScopedResource()
        let directory=self.directory
        fileQueue.async { [weak self] in
            let result=Result {try EEGRawCaptureImporter.importCapture(url,directory:directory)}
            if scoped {url.stopAccessingSecurityScopedResource()}
            DispatchQueue.main.async {
                guard let self=self else {return}
                self.fileOperation=nil
                switch result {
                case .success(let imported):
                    self.event("Imported \(imported.sampleCount) real samples; \(imported.rejectedPackets) rejected packets.")
                    self.refreshRecordings()
                    self.replay(EEGRecordingInfo(url:imported.url,sampleCount:imported.sampleCount,complete:true,corrupt:false))
                case .failure(let error):self.message=error.localizedDescription;self.refreshRecordings()
                }
            }
        }
    }
    private func event(_ text:String) { events.append(text);if events.count>50 { events.removeFirst(events.count-50) } }
}
