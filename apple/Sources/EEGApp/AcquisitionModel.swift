import SwiftUI
import CoreBluetooth
import EEGCore

final class AcquisitionModel: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate, TrialCueAcquisition {
    struct Device: Identifiable { let id: UUID; let name: String; let peripheral: CBPeripheral }
    @Published var devices: [Device] = []
    @Published var phase = "Disconnected"
    @Published var message: String?
    @Published var samples: [EEGSample] = []
    @Published private(set) var trialPlan: EEGTrialPlan?
    @Published private(set) var savingTrialPlan = false
    @Published private(set) var savingTrialRevision = false
    @Published private(set) var trialsStarted = 0
    lazy var trialCues = TrialCueController(acquisition: self)
    @Published private(set) var trial: EEGTrialEvidence?
    private var trialSession: EEGTrialSession?
    private var interruptingTrial=false
    @Published private(set) var shadowActive = false
    @Published private(set) var shadowStatus = "Stopped"
    @Published private(set) var shadowResult: EEGWindowInferenceResult?
    private var shadow: EEGLiveInference?
    private var shadowToken = UUID()
    @Published private(set) var writerStatistics: EEGQueuedRecordingStore.Statistics?
    @Published var recording = false
    @Published private(set) var finalizingRecording = false
    private let finalizationQueue=DispatchQueue(label:"cloud.autonomy.eeg.finalization",qos:.userInitiated)
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
    private var bluetoothSession = BluetoothSessionGate()
    private var decoder: EEGDecoder?
    private var metadata: [String: Data] = [:]
    private var pendingMetadata = Set<String>()
    private var dataCharacteristic: CBCharacteristic?
    private var store: EEGQueuedRecordingStore?
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
    init(storageDirectory:URL?=nil) {
        directory = storageDirectory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("EEG/Recordings",isDirectory:true)
        super.init()
        do {
            store = try EEGQueuedRecordingStore(directory:directory) { [weak self] generation,reason in
                DispatchQueue.main.async {
                    guard let self,self.recording,self.store?.generation==generation else {return}
                    self.storageFailed(NSError(domain:"EEGRecordingQueue",code:1,userInfo:[NSLocalizedDescriptionKey:reason]))
                }
            }
            refreshRecordings()
        } catch { message=error.localizedDescription }
        // Bluetooth is initialized only when the user chooses Find headset.
        freshnessTimer=Timer.scheduledTimer(withTimeInterval:0.25,repeats:true) { [weak self] _ in
            guard let self=self else {return}
            let snapshot=self.store?.statistics
            if snapshot != self.writerStatistics {self.writerStatistics=snapshot}
            guard let last=self.lastArrival,self.ready else {return}
            if ProcessInfo.processInfo.systemUptime-last>0.5 {
                self.setTransport(false,reason:"stale_input");self.stableSince=nil;self.contiguous=0
                if self.phase != "Signal stale" { self.phase="Signal stale";self.event("No recent samples; transport stability reset") }
                if ProcessInfo.processInfo.systemUptime-last > 5 { self.message="No EEG notifications for five seconds. Reconnect the headset to retry.";self.disconnect() }
            }
        }
    }
    func centralManagerDidUpdateState(_ central:CBCentralManager) { handleBluetoothState(central.state) }
    // Shared delegate path; directly exercisable without creating a radio manager.
    func handleBluetoothState(_ state:CBManagerState) {
        switch state {
        case .poweredOn:phase="Ready to scan";if scanning { beginScan() }
        case .unauthorized:
            disconnect(reason:"bluetooth_unauthorized");phase="Bluetooth permission required"
            message="Allow EEG to use Bluetooth in System Settings → Privacy & Security."
        case .poweredOff:disconnect(reason:"bluetooth_powered_off");phase="Bluetooth off"
        case .unsupported:disconnect(reason:"bluetooth_unsupported");phase="Bluetooth unavailable"
        case .resetting:disconnect(reason:"bluetooth_resetting");phase="Bluetooth resetting"
        default:
            if ready || recording { disconnect(reason:"bluetooth_unknown") }
            phase="Checking Bluetooth"
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
    func centralManager(_ central:CBCentralManager,didDiscover peripheral:CBPeripheral,advertisementData:[String:Any],rssi RSSI:NSNumber) { guard scanning else {return};add(peripheral) }
    func connect(_ device:Device) {
        guard peripheral == nil,central != nil,fileOperation==nil else { return }
        central.stopScan();scanTimer?.invalidate();scanning=false;playback=false;samples=[];sampleCount=0;decodeErrors=0;contactRaw=[:];metadata=[:];pendingMetadata=[];dataCharacteristic=nil;decoder=nil;configuring=false;ready=false;previewBuffer=[];transportStable=false;lastArrival=nil;stableSince=nil;contiguous=0;origin=ProcessInfo.processInfo.systemUptime
        guard bluetoothSession.begin(device.id) else {return}
        peripheral=device.peripheral;device.peripheral.delegate=self;phase="Connecting to \(device.name)";central.connect(device.peripheral);startDeadline(seconds:15,message:"Headset connection timed out.")
    }
    func centralManager(_ central:CBCentralManager,didConnect peripheral:CBPeripheral) { guard accepts(peripheral) else {return};startDeadline(seconds:10,message:"Device metadata timed out. Disconnect other readers and reconnect.");phase="Reading device configuration";peripheral.discoverServices([service,CBUUID(string:"180A")]) }
    func centralManager(_ central:CBCentralManager,didFailToConnect peripheral:CBPeripheral,error:Error?) { guard self.peripheral === peripheral,bluetoothSession.finish(peripheral.identifier) else {return};connectionTimer?.invalidate();self.peripheral=nil;phase="Connection failed";message=error?.localizedDescription }
    func centralManager(_ central:CBCentralManager,didDisconnectPeripheral peripheral:CBPeripheral,error:Error?) {
        guard self.peripheral === peripheral,bluetoothSession.finish(peripheral.identifier) else {return}
        connectionTimer?.invalidate();configuring=false;
        event("Disconnected"+(error.map{": "+$0.localizedDescription} ?? ""));setTransport(false,reason:"disconnected");if recording { stopRecording() };self.peripheral=nil;ready=false;transportStable=false;phase="Disconnected"
    }
    func peripheral(_ peripheral:CBPeripheral,didDiscoverServices error:Error?) {
        guard accepts(peripheral) else {return}
        if let error=error { fail(error);return }
        guard let services=peripheral.services else { return }
        pendingMetadata=Set([serialID,revisionID,configID])
        for s in services { peripheral.discoverCharacteristics(nil,for:s) }
    }
    func peripheral(_ peripheral:CBPeripheral,didDiscoverCharacteristicsFor service:CBService,error:Error?) {
        guard accepts(peripheral) else {return}
        if let error=error { fail(error);return }
        for c in service.characteristics ?? [] {
            let key=c.uuid.uuidString.uppercased()
            if key==dataID { dataCharacteristic=c }
            if pendingMetadata.contains(key) { peripheral.readValue(for:c) }
        }
        configureIfPossible()
    }
    private func accepts(_ peripheral:CBPeripheral)->Bool {
        self.peripheral === peripheral && bluetoothSession.accepts(peripheral.identifier)
    }
    private func configureIfPossible() {
        guard let peripheral,accepts(peripheral) else {return}
        guard !ready,!configuring,let serial=metadata[serialID],let revision=metadata[revisionID],!pendingMetadata.contains(configID),let c=dataCharacteristic else { return }
        do {
            decoder=try EEGDecoder(serial:serial,revision:revision,configuration:metadata[configID]);configuring=true;startDeadline(seconds:8,message:"Headset notifications did not start.");peripheral.setNotifyValue(true,for:c);phase="Starting signal stream"
        } catch { fail(error) }
    }
    func peripheral(_ peripheral:CBPeripheral,didUpdateNotificationStateFor characteristic:CBCharacteristic,error:Error?) {
        guard accepts(peripheral) else {return}
        if let error=error { fail(error);return };guard characteristic.uuid.uuidString.uppercased()==dataID else { return };connectionTimer?.invalidate();ready=characteristic.isNotifying;lastArrival=ProcessInfo.processInfo.systemUptime;phase=ready ? "Listening · stabilizing":"Notifications stopped"
    }
    func peripheral(_ peripheral:CBPeripheral,didUpdateValueFor characteristic:CBCharacteristic,error:Error?) {
        guard accepts(peripheral) else {return}
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
            if recording { try store?.enqueueEvent(kind:"ble_notification",fields:["hex":data.map{String(format:"%02x",$0)}.joined(),"receivedAt":String(now-origin)]) }
        } catch { storageFailed(error);return }
        let decoded:[EEGSample]
        do { decoded=try decoder!.decode(packet:data,receivedAt:now-origin) }
        catch {
            decodeErrors+=1;setTransport(false,reason:"rejected_packet",receivedAt:now-origin);stableSince=nil;contiguous=0;lastArrival=now
            event("Rejected packet: "+error.localizedDescription)
            do { if recording { try store?.enqueueEvent(kind:"decode_error",fields:["message":error.localizedDescription,"receivedAt":String(now-origin)]) } }
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
                if recording { try store?.enqueue(sample:sample) }
                if let shadow,!shadow.submit(.sample(sample)) { stopShadow(reason:"inference_overload") }
                let slot=Int(sample.counter)%64
                if metadata[configID]==Data([1,128,0,16,32,16]),slot<14,sample.adcWords.count==15 { contactRaw[Self.channels[slot]]=sample.adcWords[7] }
            }
        } catch { storageFailed(error) }
    }
    private func recordTransport(reason:String,receivedAt:Double?=nil) throws {
        try store?.enqueueEvent(kind:"transport_status",fields:["status":transportStable ? "stable":"recovering",
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
    /// Stop admission and cues immediately; suspension may preempt finalization.
    /// No automatic resume can reuse the former trial or inference state.
    func prepareForSuspension(reason:String) {
        trialCues.stop(reason:reason,announce:false)
        disconnect(reason:reason)
        phase="Suspended — reconnect to start a new recording"
    }
    /// Called on orderly lifecycle shutdown. Forced kill leaves the file incomplete.
    func prepareForTermination() {
        disconnect()
        // Orderly termination retains its durability barrier. Normal Stop does
        // not block the UI; forced termination can still leave an incomplete file.
        finalizationQueue.sync {}
    }
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
    func disconnect(reason:String = "disconnect_requested") { bluetoothSession.cancel();connectionTimer?.invalidate();scanTimer?.invalidate();central?.stopScan();scanning=false;configuring=false;setTransport(false,reason:reason);if recording { stopRecording() };if let p=peripheral { central?.cancelPeripheralConnection(p) };ready=false;transportStable=false }
    func startRecording() {
        guard ready,!recording,!finalizingRecording,!playback,fileOperation==nil,let store=store else { return }
        do {
            let url=try store.start();recording=true
            trial=nil;trialPlan=nil;savingTrialPlan=false;savingTrialRevision=false;interruptingTrial=false;trialsStarted=0;trialSession=EEGTrialSession()
            let anchor = try EEGRecordingClockAnchor.capture(receiptClock: { self.recordingClock })
            let anchorJSON = String(decoding: try JSONEncoder().encode(anchor), as: UTF8.self)
            try store.enqueueEvent(kind:"recording_clock_anchor",fields:["json":anchorJSON])
            try store.enqueueEvent(kind:"device_metadata",fields:metadata.mapValues{$0.map{String(format:"%02x",$0)}.joined()})
            try recordTransport(reason:"recording_start")
            event("Recording started: "+url.lastPathComponent)
        } catch { storageFailed(error) }
    }
    func stopRecording() {
        guard recording else { return }
        stopShadow(reason:"recording_stopped")
        interruptTrial(reason: "recording_stopped")
        guard recording else { return }
        do { try store?.enqueueEvent(kind:"transport_checkpoint",fields:["stable":String(transportStable),"decode_errors":String(decodeErrors),"receivedAt":String(ProcessInfo.processInfo.systemUptime-origin)]) } catch { storageFailed(error);return }
        guard let store else {return}
        // Admission is stopped on the acquisition executor before ownership of
        // the final barrier transfers to the finalization queue. Restart and
        // file operations remain disabled until its completion returns.
        recording=false;finalizingRecording=true
        event("Recording input stopped; finalization pending")
        finalizationQueue.async { [weak self] in
            let result=Result {try store.finish()}
            DispatchQueue.main.async {
                guard let self else {return}
                self.finalizingRecording=false
                switch result {
                case .success: self.event("Recording finalized")
                case .failure(let error):
                    self.message="Recording finalization failed: "+error.localizedDescription
                    self.event("Recording finalization failed; file is incomplete or uncertain")
                }
                self.refreshRecordings()
            }
        }
    }
    /// Uses exactly the receipt clock used by the decoder, not wall-clock time.
    var recordingClock: Double { ProcessInfo.processInfo.systemUptime-origin }
    func commitTrialPlan(participantID: String, sessionID: String, controls: Bool = false) throws {
        guard recording,!savingTrialPlan,trialPlan == nil,trial == nil,let store else { throw EEGTrialEvidence.Failure.invalidTransition }
        let plan = try EEGTrialPlan(sessionID: sessionID,participantID: participantID,seed: UInt64.random(in: .min ... .max),controls:controls)
        let json = String(decoding: try JSONEncoder().encode(plan),as: UTF8.self)
        savingTrialPlan=true
        let generation=store.generation
        do {
            try store.enqueueEvent(kind: "trial_plan",fields: ["json":json,"receivedAt":String(recordingClock)]) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self,self.store?.generation==generation else {return}
                    self.savingTrialPlan=false
                    guard self.recording else {return}
                    switch result {
                    case .success: self.trialPlan=plan
                    case .failure(let error): self.storageFailed(error)
                    }
                }
            }
        } catch { savingTrialPlan=false;storageFailed(error);throw error }
    }
    func nextPlannedTrial() throws -> EEGTrialEvidence {
        guard let trialPlan else { throw EEGTrialEvidence.Failure.invalidTransition }
        do { return try trialPlan.next(after:trial,started:trialsStarted,at:recordingClock) }
        catch EEGTrialEvidence.Failure.readinessMissing {
            throw NSError(domain: "EEGTrialPlan",code:1,userInfo:[NSLocalizedDescriptionKey:"Rest before the next trial: at least 10 seconds after review or interruption, or 60 seconds after each block of eight."])
        }
    }
    func submitTrialBegin(_ planned:EEGTrialEvidence,completion:@escaping(Result<Void,Error>)->Void) throws {
        guard recording,ready,transportStable,!playback,let trialSession else {throw EEGTrialEvidence.Failure.readinessMissing}
        let expected=try nextPlannedTrial()
        guard planned.id==expected.id,planned.sessionID==expected.sessionID,
              planned.participantID==expected.participantID,planned.requestedCondition==expected.requestedCondition,
              planned.startingNumber==expected.startingNumber else {throw EEGTrialEvidence.Failure.invalidTransition}
        try persistTrialRevision(trialSession.prepareBegin(planned)) { [weak self] result in
            if case .success=result {self?.trialsStarted+=1}
            completion(result)
        }
    }
    func trialObservationTime(uptime:Double)->Double {uptime-origin}
    func submitTrialTransition(_ change:(inout EEGTrialEvidence,Double)throws->Void,
                               at:Double?=nil,completion:((Result<Void,Error>)->Void)?=nil) throws {
        guard recording,let trialSession else {throw EEGRecordingError.notRecording}
        try persistTrialRevision(trialSession.prepareTransition(at:at ?? recordingClock,change),completion:completion)
    }
    private func persistTrialRevision(_ revision:EEGTrialSession.Revision,
                                      completion:((Result<Void,Error>)->Void)?) throws {
        guard let trialSession,let store else {throw EEGRecordingError.notRecording}
        let generation=store.generation
        savingTrialRevision=true
        do {
            try store.enqueueTrialEvidence(revision.evidence) { [weak self,weak trialSession] result in
                DispatchQueue.main.async {
                    guard let self,let trialSession,self.trialSession === trialSession,
                          self.store?.generation==generation else {completion?(.failure(EEGRecordingError.notRecording));return}
                    self.savingTrialRevision=false
                    do {try trialSession.acknowledge(revision,result:result)}
                    catch EEGTrialSession.Failure.staleAcknowledgement {completion?(.failure(EEGTrialSession.Failure.staleAcknowledgement));return}
                    catch {
                        if self.recording {self.storageFailed(error)}
                        self.trial=trialSession.trial;completion?(.failure(error));return
                    }
                    self.trial=trialSession.trial;completion?(.success(()))
                }
            }
        } catch {
            savingTrialRevision=false
            try? trialSession.acknowledge(revision,result:.failure(error))
            trial=trialSession.trial;storageFailed(error);throw error
        }
    }
    func cancelTrial(reason:String) {interruptTrial(reason:reason)}
    private func interruptTrial(reason: String) {
        guard !interruptingTrial,let trialSession,trialSession.active || trialSession.pending != nil else {return}
        do {
            if trialSession.pending != nil {
                try trialSession.invalidatePending(reason:reason,at:recordingClock)
                throw EEGTrialSession.Failure.persistenceUnavailable
            }
            interruptingTrial=true
            let generation=store?.generation
            try submitTrialTransition({try $0.interrupt(reason:reason,at:$1)}) { [weak self] _ in
                guard let self,self.store?.generation==generation else {return}
                self.interruptingTrial=false
            }
        } catch {
            interruptingTrial=false
            // Uncertain evidence cannot be finalized. Do not recurse through
            // storageFailed when interruption itself could not be persisted.
            store?.abort();recording=false;refreshRecordings()
            message="Trial evidence could not be saved: "+error.localizedDescription
        }
        trial=trialSession.trial
    }
    func startShadow(profile: EEGMentalProfile, sessionID: String, participantConfirmed: Bool,
                     maximumPendingInputs: Int, maximumPendingEventBytes: Int) throws {
        guard participantConfirmed,recording,ready,transportStable,!playback,!shadowActive,let store else { throw EEGTrialEvidence.Failure.readinessMissing }
        guard !profile.trainingSessions.contains(sessionID) else { throw EEGReplayInference.Failure.trainingRecording }
        let token=UUID();shadowToken=token
        let consumer=try EEGLiveInference(profile:profile,participantID:profile.participantID,sessionID:sessionID,
            maximumPendingInputs:maximumPendingInputs,maximumPendingEventBytes:maximumPendingEventBytes) { [weak self] output in
            DispatchQueue.main.async {
                guard let self,self.shadowToken == token,self.shadowActive,
                      self.shadow?.generation == output.generation else { return }
                if let failure=output.failure { self.stopShadow(reason:failure);return }
                guard let row=output.window else { return }
                do {
                    try self.store?.enqueueEvent(kind:"shadow_inference",fields:["profile_id":profile.id,
                        "feature_config_id":EEGMentalFeatures.configurationID,"session_id":sessionID,
                        "ordinal":String(row.ordinal),"candidate":row.candidate ?? "",
                        "shadow_run_id":token.uuidString,"generation":String(output.generation),
                        "first_sample_index":row.firstSampleIndex.map(String.init) ?? "",
                        "last_sample_index":row.lastSampleIndex.map(String.init) ?? "",
                        "sample_count":String(row.sampleCount),
                        "input_start":row.inputStart.map { String($0) } ?? "",
                        "input_end":row.inputEnd.map { String($0) } ?? "",
                        "time_basis":"recorded_receipt_seconds",
                        "has_candidate":String(row.candidate != nil),"reasons":row.reasons.joined(separator:";"),
                        "status":row.status,"system_control_enabled":"false","receivedAt":String(self.recordingClock)])
                    self.shadowResult=row;self.shadowStatus="Experimental shadow result — recording queued; no reliable command"
                } catch { self.storageFailed(error) }
            }
        }
        // Admission failure is an inference configuration error, not a storage failure.
        do {
            let device=metadata.mapValues { $0.map { String(format:"%02x",$0) }.joined() }.merging(["kind":"device_metadata"]) { _,new in new }
            guard consumer.submit(.event(try JSONSerialization.data(withJSONObject:device))),
                  consumer.submit(.event(try JSONSerialization.data(withJSONObject:["kind":"transport_status","status":"stable"]))) else { throw EEGLiveInference.Failure.invalidCapacity }
        } catch { consumer.stop();throw error }
        do {
            try store.enqueueEvent(kind:"shadow_start",fields:["profile_id":profile.id,"participant_id":profile.participantID,
                "session_id":sessionID,"feature_config_id":EEGMentalFeatures.configurationID,"shadow_run_id":token.uuidString,
                "maximum_pending_inputs":String(maximumPendingInputs),
                "maximum_pending_event_bytes":String(maximumPendingEventBytes),
                "system_control_enabled":"false","receivedAt":String(recordingClock)].merging(EEGShadowVerification.implementationFields) { _,new in new })
            shadow=consumer;shadowActive=true;shadowResult=nil;shadowStatus="Waiting for validated windows"
        } catch { consumer.stop();storageFailed(error);throw error }
    }
    func stopShadow(reason: String = "operator_stopped", persist: Bool = true) {
        guard shadow != nil else { return }
        let stoppedRun=shadowToken
        shadow?.stop();shadow=nil;shadowToken=UUID();shadowActive=false;shadowResult=nil;shadowStatus="Stopped: "+reason
        if persist,recording {
            do { try store?.enqueueEvent(kind:"shadow_stop",fields:["shadow_run_id":stoppedRun.uuidString,"reason":reason,"receivedAt":String(recordingClock)]) }
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
        guard !recording,!finalizingRecording,peripheral==nil,fileOperation==nil else {message="Finish the current operation and disconnect before replay.";return}
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
    func export(_ info:EEGRecordingInfo,to destination:URL,format:EEGRecordingStore.ExportFormat = .csv,units:EEGRecordingStore.Units = .adc,completion:@escaping(Bool)->Void = {_ in}) {
        guard !recording,!finalizingRecording,peripheral==nil,fileOperation==nil else {message="Finish the current operation and disconnect before exporting.";completion(false);return}
        fileOperation="Exporting recording";let directory=self.directory
        fileQueue.async { [weak self] in
            let result=Result {
                let store = try EEGRecordingStore(directory:directory)
                switch format {
                case .native: try store.exportNative(recording:info.url,to:destination)
                case .csv: try store.exportCSV(recording:info.url,to:destination,units:units)
                }
            }
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
        do { try store?.enqueueEvent(kind:"annotation",fields:["text":String(text.prefix(1000)),"receivedAt":String(ProcessInfo.processInfo.systemUptime-origin)]);event("Marker queued: "+text) } catch { storageFailed(error) }
    }
    /// A single document entry point with explicit format-specific validation.
    func importCapture(_ url: URL) {
        if url.pathExtension == "jsonl" { importNativeRecording(url) }
        else { importRawCapture(url) }
    }
    private func importNativeRecording(_ url: URL) {
        guard !recording,!finalizingRecording,peripheral==nil,fileOperation==nil else {message="Finish the current operation and disconnect before importing.";return}
        guard url.isFileURL else {message="Import requires a local recording file.";return}
        fileOperation="Importing native recording"
        let scoped=url.startAccessingSecurityScopedResource(), directory=self.directory
        fileQueue.async { [weak self] in
            let result=Result {try EEGRecordingStore(directory:directory).importNative(url)}
            if scoped {url.stopAccessingSecurityScopedResource()}
            DispatchQueue.main.async {
                guard let self else {return}
                self.fileOperation=nil
                switch result {
                case .success(let info):
                    self.event("Imported native recording: \(info.sampleCount) samples; \(info.complete ? "finalized" : "incomplete").")
                    self.refreshRecordings();self.replay(info)
                case .failure(let error):self.message=error.localizedDescription;self.refreshRecordings()
                }
            }
        }
    }
    /// Import work is isolated from main-thread interaction and Bluetooth callbacks.
    func importRawCapture(_ url:URL) {
        guard !recording,!finalizingRecording,peripheral==nil,fileOperation==nil else {message="Finish the current operation and disconnect before importing.";return}
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

/// Stop closes admission immediately; retain the identity until CoreBluetooth's
/// terminal callback so reconnect cannot overlap a still-cancelling connection.
struct BluetoothSessionGate {
    private var id:UUID?
    private var cancelled=false
    mutating func begin(_ id:UUID)->Bool {
        guard self.id == nil else {return false}
        self.id=id;cancelled=false;return true
    }
    func accepts(_ id:UUID)->Bool {self.id==id && !cancelled}
    mutating func cancel() {cancelled=true}
    mutating func finish(_ id:UUID)->Bool {
        guard self.id==id else {return false}
        self.id=nil;cancelled=false;return true
    }
}
