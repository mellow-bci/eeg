import Foundation

public struct EEGImportResult: Sendable {
    public let url:URL
    public let sampleCount:Int
    public let rejectedPackets:Int
}

/// Real raw packets pass through the same decoder as acquisition. Call on a worker queue.
public enum EEGRawCaptureImporter {
    public static func importCapture(_ url:URL,directory:URL) throws -> EEGImportResult {
        let store=try EEGRecordingStore(directory:directory)
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
            try store.finish();started=false
            return EEGImportResult(url:output,sampleCount:imported.sampleCount,rejectedPackets:rejected)
        } catch {
            if started {try? store.appendEvent(kind:"import_failed",fields:["message":error.localizedDescription]);try? store.finish()}
            throw error
        }
    }
    private enum ImportError:Error,LocalizedError {
        case invalid(String)
        var errorDescription:String? {if case .invalid(let message)=self {return message};return nil}
    }
    private static func hexData(_ hex:String) throws -> Data {
        guard hex.count%2==0 else {throw ImportError.invalid("Malformed hexadecimal packet.")}
        var bytes:[UInt8]=[];var i=hex.startIndex
        while i<hex.endIndex {let next=hex.index(i,offsetBy:2);guard let value=UInt8(hex[i..<next],radix:16) else {throw ImportError.invalid("Malformed hexadecimal packet.")};bytes.append(value);i=next}
        return Data(bytes)
    }
}
