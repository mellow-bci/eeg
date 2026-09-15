import Foundation

/// One recording writer. High-rate admission is nonblocking; control/evidence
/// calls are ordered barriers and must be made by the same host as admission.
/// A successful enqueue is not a durability acknowledgement. Failure aborts
/// without a completion marker. Never call a control method from onFailure.
public final class EEGQueuedRecordingStore {
    public enum Failure: Error { case invalidCapacity, admissionRejected, aborted }
    private enum Input { case sample(EEGSample), event(String,[String:String]) }
    private let store: EEGRecordingStore
    private let queue: DispatchQueue
    private let lock=NSLock()
    private let capacity: Int
    private let byteCapacity: Int
    private var pending=0, bytes=0
    private var active=false
    private var failed=false
    private var epoch: UInt64=0
    private let onFailure: (UInt64,String)->Void
    public convenience init(directory: URL, maximumPendingInputs: Int=1024,
                            maximumPendingBytes: Int=4*1024*1024,
                            onFailure: @escaping (UInt64,String)->Void) throws {
        try self.init(store:EEGRecordingStore(directory:directory),maximumPendingInputs:maximumPendingInputs,
            maximumPendingBytes:maximumPendingBytes,queue:DispatchQueue(label:"cloud.autonomy.eeg.recording",qos:.userInitiated),onFailure:onFailure)
    }
    init(store: EEGRecordingStore, maximumPendingInputs: Int=1024, maximumPendingBytes: Int=4*1024*1024,
         queue: DispatchQueue, onFailure: @escaping (UInt64,String)->Void) throws {
        guard maximumPendingInputs>0,maximumPendingBytes>0 else { throw Failure.invalidCapacity }
        self.store=store;capacity=maximumPendingInputs;byteCapacity=maximumPendingBytes
        self.queue=queue;self.onFailure=onFailure
    }
    public var generation: UInt64 { lock.lock();defer {lock.unlock()};return epoch }
    public var pendingInputs: Int { lock.lock();defer {lock.unlock()};return pending }
    public var pendingPayloadBytes: Int { lock.lock();defer {lock.unlock()};return bytes }
    @discardableResult public func start() throws -> URL {
        try queue.sync {
            lock.lock();let already=active;lock.unlock()
            guard !already else { throw EEGRecordingError.alreadyRecording }
            let url=try store.start()
            lock.lock();epoch &+= 1;failed=false;active=true;lock.unlock()
            return url
        }
    }
    public func enqueue(sample: EEGSample) throws {
        // Fixed channel cardinality bounds dictionary storage. Account 512 bytes
        // for its logical values/keys; this is not a process-RSS estimate.
        guard sample.adcWords.count==15,sample.electrodesADC.count==14,
              sample.electrodesMicrovolts == nil || sample.electrodesMicrovolts?.count==14,
              (try? EEGRecordingStore.validateSample(sample)) != nil else {
            reject("invalid_sample");throw EEGRecordingError.invalidData
        }
        try enqueue(.sample(sample),cost:512)
    }
    public func enqueueEvent(kind: String,fields: [String:String]) throws {
        var cost=kind.utf8.count
        guard cost<=byteCapacity else { reject("event_capacity");throw Failure.admissionRejected }
        for (key,value) in fields {
            for count in [key.utf8.count,value.utf8.count] {
                guard count<=byteCapacity-cost else { reject("event_capacity");throw Failure.admissionRejected }
                cost+=count
            }
        }
        try enqueue(.event(kind,fields),cost:max(1,cost))
    }
    private func enqueue(_ input: Input,cost: Int) throws {
        lock.lock()
        guard active,!failed else { lock.unlock();throw Failure.aborted }
        guard pending<capacity,cost<=byteCapacity-bytes else {
            lock.unlock();reject("recording_queue_overload");throw Failure.admissionRejected
        }
        pending+=1;bytes+=cost
        queue.async { [self] in
            defer {lock.lock();pending-=1;bytes-=cost;lock.unlock()}
            lock.lock();let usable=active && !failed;lock.unlock()
            guard usable else { return }
            do {
                switch input {
                case .sample(let sample): try store.append(sample:sample)
                case .event(let kind,let fields): try store.appendEvent(kind:kind,fields:fields)
                }
            } catch { reject("recording_write_failed: \(error)") }
        }
        lock.unlock()
    }
    private func reject(_ reason: String) {
        lock.lock()
        guard active,!failed else {lock.unlock();return}
        failed=true;active=false;let generation=epoch
        queue.async { [self] in store.abort();onFailure(generation,reason) }
        lock.unlock()
    }
    private func barrier(_ operation: () throws -> Void) throws {
        try queue.sync {
            lock.lock();let usable=active && !failed;lock.unlock()
            guard usable else {throw Failure.aborted}
            do {try operation()} catch {reject("recording_control_failed: \(error)");throw error}
        }
    }
    public func appendEvent(kind:String,fields:[String:String]) throws {
        try barrier {try store.appendEvent(kind:kind,fields:fields)}
    }
    public func appendTrialEvidence(_ trial: EEGTrialEvidence) throws {
        try barrier {try store.appendTrialEvidence(trial)}
    }
    public func finish() throws {
        try barrier {
            try store.finish()
            lock.lock();active=false;lock.unlock()
        }
    }
    public func abort() {
        lock.lock();active=false;lock.unlock()
        queue.sync {store.abort()}
    }
}
