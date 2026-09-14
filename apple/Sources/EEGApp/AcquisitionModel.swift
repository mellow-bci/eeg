import SwiftUI
import CoreBluetooth
import EEGCore

final class AcquisitionModel: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    struct Device: Identifiable { let id: UUID; let name: String; let peripheral: CBPeripheral }
    @Published var devices: [Device] = []
    @Published var phase = "Disconnected"
    @Published var message: String?
    @Published var samples: [EEGSample] = []
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
        guard peripheral == nil else { return }
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
        guard peripheral == nil,central != nil else { return }
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
        event("Recording storage failed: "+error.localizedDescription)
        stopRecording()
        message="Recording stopped after a storage failure: "+error.localizedDescription
    }
    private func fail(_ error:Error) { message=error.localizedDescription;event(error.localizedDescription);disconnect() }
    func disconnect() { connectionTimer?.invalidate();scanTimer?.invalidate();central?.stopScan();scanning=false;configuring=false;setTransport(false,reason:"disconnect_requested");if recording { stopRecording() };if let p=peripheral { central?.cancelPeripheralConnection(p) };ready=false;transportStable=false }
    func startRecording() {
        guard ready,!recording,!playback,let store=store else { return }
        do {
            let url=try store.start();recording=true
            try store.appendEvent(kind:"device_metadata",fields:metadata.mapValues{$0.map{String(format:"%02x",$0)}.joined()})
            try recordTransport(reason:"recording_start")
            event("Recording started: "+url.lastPathComponent)
        } catch { message=error.localizedDescription;if recording { stopRecording() } }
    }
    func stopRecording() {
        guard recording else { return }
        do { try store?.appendEvent(kind:"transport_checkpoint",fields:["stable":String(transportStable),"decode_errors":String(decodeErrors),"receivedAt":String(ProcessInfo.processInfo.systemUptime-origin)]) } catch { message=error.localizedDescription }
        do { try store?.finish() } catch { message=error.localizedDescription }
        recording=false;refreshRecordings();event("Recording stopped")
    }
    func refreshRecordings() { do { recordings=try store?.inventory() ?? [] } catch { message=error.localizedDescription } }
    func replay(_ info:EEGRecordingInfo,offset:Int=0) {
        guard !recording,!ready else { message="Disconnect the headset before opening a recording.";return }
        do { samples=try store?.replay(recording:info.url,offset:offset,limit:1280) ?? [];selectedRecording=info.url;playback=true;sampleCount=info.sampleCount;replayOffset=offset;phase="Recorded data · replay" } catch { message=error.localizedDescription }
    }
    @discardableResult func export(_ info:EEGRecordingInfo,to destination:URL) -> Bool {
        guard !recording,peripheral==nil else {message="Disconnect the headset before exporting a recording.";return false}
        do { guard let store=store else {return false};try store.exportCSV(recording:info.url,to:destination);event("Exported "+destination.lastPathComponent);return true } catch { message=error.localizedDescription;return false } }
    func annotate(_ text:String) {
        guard recording,!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return }
        do { try store?.appendEvent(kind:"annotation",fields:["text":String(text.prefix(1000)),"receivedAt":String(ProcessInfo.processInfo.systemUptime-origin)]);event("Marker: "+text) } catch { message=error.localizedDescription;stopRecording() }
    }
    /// Import an actual raw BLE capture through the same decoder used by Bluetooth.
    /// Bounded input size prevents accidentally loading an arbitrarily large JSON object.
    func importRawCapture(_ url:URL) {
        guard !recording,peripheral==nil,let store=store else {message="Disconnect before importing a capture.";return}
        guard url.isFileURL else {message="Import requires a local capture file.";return}
        let scoped=url.startAccessingSecurityScopedResource();defer {if scoped {url.stopAccessingSecurityScopedResource()}}
        var started=false
        do {
            let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
            guard size>0,size<=64*1024*1024 else {throw ImportError.invalid("Choose a raw capture JSON up to 64 MiB.")}
            let raw=try Data(contentsOf:url)
            guard let object=try JSONSerialization.jsonObject(with:raw) as? [String:Any],
                  let info=object["info"] as? [String:Any],let packets=object["packets"] as? [[String:Any]] else {throw ImportError.invalid("Expected a raw BLE capture with info and packets fields.")}
            func value(_ key:String) throws -> Data {
                let entry=info[key]
                guard let hex=(entry as? String) ?? ((entry as? [String:Any])?["hex"] as? String) else {throw ImportError.invalid("Missing device metadata: "+key)}
                return try hexData(hex)
            }
            let config=info[EPOCProtocol.configurationCharacteristic] == nil ? nil : try value(EPOCProtocol.configurationCharacteristic)
            var imported=try EEGDecoder(serial:value(EPOCProtocol.serialCharacteristic),revision:value(EPOCProtocol.revisionCharacteristic),configuration:config)
            let output=try store.start();started=true
            try store.appendEvent(kind:"import_source",fields:["format":"raw_ble_capture","name":url.lastPathComponent])
            try store.appendEvent(kind:"device_metadata",fields:["metadata_json":String(decoding:try JSONSerialization.data(withJSONObject:info),as:UTF8.self)])
            var rejected=0
            var importStable=false
            var importSince:Double?
            var importLast:Double?
            var importContiguous=0
            func importStatus(_ stable:Bool,reason:String,at:Double,force:Bool=false) throws {
                guard importStable != stable || force else {return}
                importStable=stable
                try store.appendEvent(kind:"transport_status",fields:["status":stable ? "stable":"recovering","reason":reason,"receivedAt":String(at),"calibrated":String(imported.voltageDivisor != nil),"physiology_validated":"false"])
            }
            try importStatus(false,reason:"import_start",at:0,force:true)
            for packet in packets {
                guard let uuid=packet["uuid"] as? String,uuid.lowercased()==EPOCProtocol.dataCharacteristic else {continue}
                guard let hex=packet["hex"] as? String,let time=packet["t"] as? Double,time.isFinite else {throw ImportError.invalid("Malformed raw packet.")}
                try store.appendEvent(kind:"ble_notification",fields:["hex":hex,"receivedAt":String(time)])
                let decoded:[EEGSample]
                do {decoded=try imported.decode(packet:hexData(hex),receivedAt:time)}
                catch {rejected+=1;try store.appendEvent(kind:"decode_error",fields:["message":error.localizedDescription,"receivedAt":String(time)]);try importStatus(false,reason:"rejected_packet",at:time);importSince=nil;importContiguous=0;importLast=time;continue}
                let gap=importLast.map{time-$0>0.5 || time<$0} ?? false
                if gap || decoded.contains(where:{!$0.continuous}) {importSince=nil;importContiguous=0;try importStatus(false,reason:"sample_gap",at:time)}
                else if importSince==nil {importSince=time}
                else {importContiguous+=decoded.count;try importStatus(importContiguous>=256 && time-(importSince ?? time)>=2,reason:"contiguous_sample_counters",at:time)}
                importLast=time
                for sample in decoded {try store.append(sample:sample)}
            }
            try store.appendEvent(kind:"import_complete",fields:["decode_errors":String(rejected)])
            try store.finish();started=false;refreshRecordings()
            if let item=recordings.first(where:{$0.url==output}) {replay(item)}
            event("Imported \(imported.sampleCount) real samples; \(rejected) rejected packets.")
        } catch {
            if started {try? store.appendEvent(kind:"import_failed",fields:["message":error.localizedDescription]);try? store.finish()}
            refreshRecordings();message=error.localizedDescription
        }
    }
    private enum ImportError:Error,LocalizedError {
        case invalid(String)
        var errorDescription:String? {if case .invalid(let message)=self {return message};return nil}
    }
    private func hexData(_ hex:String) throws -> Data {
        guard hex.count%2==0 else {throw ImportError.invalid("Malformed hexadecimal packet.")}
        var bytes:[UInt8]=[];var i=hex.startIndex
        while i<hex.endIndex {let next=hex.index(i,offsetBy:2);guard let value=UInt8(hex[i..<next],radix:16) else {throw ImportError.invalid("Malformed hexadecimal packet.")};bytes.append(value);i=next}
        return Data(bytes)
    }
    private func event(_ text:String) { events.append(text);if events.count>50 { events.removeFirst(events.count-50) } }
}
