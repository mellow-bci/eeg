import Foundation

/// One recording writer. High-rate admission is nonblocking; control/evidence
/// calls are ordered barriers and must be made by the same host as admission.
/// A successful enqueue is not a durability acknowledgement. Failure aborts
/// without a completion marker. Failure notifications run on a separate serial
/// queue and do not acknowledge file closure. Never call a control method from onFailure.
public final class EEGQueuedRecordingStore {
    public enum Failure: Error, LocalizedError {
        case invalidCapacity, admissionRejected, aborted, cleanupPending
        public var errorDescription: String? {
            switch self {
            case .invalidCapacity: return "Recording queue limits must be positive."
            case .admissionRejected: return "Recording queue capacity was exceeded; capture is incomplete."
            case .aborted: return "Recording is inactive or aborted."
            case .cleanupPending: return "Storage cleanup is still pending. Wait before starting another recording."
            }
        }
    }
    public struct Statistics: Sendable, Equatable {
        public let generation: UInt64
        public let pendingInputs: Int
        public let pendingPayloadBytes: Int
        public let admittedInputs: Int
        public let writtenInputs: Int
        public let discardedInputs: Int
        public let failedWrites: Int
        public let peakPendingInputs: Int
        public let peakPendingPayloadBytes: Int
        public let maximumQueueWaitSeconds: Double
        public let maximumWriteSeconds: Double
        public let failed: Bool
        public let cleanupPending: Bool
    }
    private var admitted=0, written=0, discarded=0, writeFailures=0, peakInputs=0, peakBytes=0
    private var maximumWait=0.0, maximumWrite=0.0
    private enum Input { case sample(EEGSample), event(String,[String:String],Bool) }
    private let store: EEGRecordingStore
    private let queue: DispatchQueue
    private let notifications=DispatchQueue(label:"cloud.autonomy.eeg.recording.failures")
    private let lock=NSLock()
    private let capacity: Int
    private let byteCapacity: Int
    private var pending=0, bytes=0
    private var active=false
    private var failed=false
    private var cleanupPending=false
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
    public var statistics: Statistics {
        lock.lock();defer {lock.unlock()}
        return Statistics(generation:epoch,pendingInputs:pending,pendingPayloadBytes:bytes,
            admittedInputs:admitted,writtenInputs:written,discardedInputs:discarded,failedWrites:writeFailures,
            peakPendingInputs:peakInputs,peakPendingPayloadBytes:peakBytes,
            maximumQueueWaitSeconds:maximumWait,maximumWriteSeconds:maximumWrite,failed:failed,cleanupPending:cleanupPending)
    }
    @discardableResult public func start() throws -> URL {
        lock.lock();let cleaning=cleanupPending;let alreadyActive=active;lock.unlock()
        guard !cleaning else {throw Failure.cleanupPending}
        guard !alreadyActive else {throw EEGRecordingError.alreadyRecording}
        return try queue.sync {
            lock.lock();let already=active;lock.unlock()
            guard !already else { throw EEGRecordingError.alreadyRecording }
            let url=try store.start()
            lock.lock();epoch &+= 1;failed=false;active=true
            admitted=0;written=0;discarded=0;writeFailures=0;peakInputs=0;peakBytes=0;maximumWait=0;maximumWrite=0
            lock.unlock()
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
    /// With onPersisted, completion follows write + filesystem synchronize, not
    /// admission. Completion runs on the notification queue. This is not a
    /// hardware power-loss guarantee. Rejected admission throws without callback.
    public func enqueueEvent(kind: String,fields: [String:String],
                             onPersisted: ((Result<Void,Error>)->Void)? = nil) throws {
        var cost=kind.utf8.count
        guard cost<=byteCapacity else { reject("event_capacity");throw Failure.admissionRejected }
        for (key,value) in fields {
            for count in [key.utf8.count,value.utf8.count] {
                guard count<=byteCapacity-cost else { reject("event_capacity");throw Failure.admissionRejected }
                cost+=count
            }
        }
        try enqueue(.event(kind,fields,onPersisted != nil),cost:max(1,cost),completion:onPersisted)
    }
    private func enqueue(_ input: Input,cost: Int,completion: ((Result<Void,Error>)->Void)? = nil) throws {
        lock.lock()
        guard active,!failed else { lock.unlock();throw Failure.aborted }
        guard pending<capacity,cost<=byteCapacity-bytes else {
            lock.unlock();reject("recording_queue_overload");throw Failure.admissionRejected
        }
        pending+=1;bytes+=cost;admitted+=1
        peakInputs=max(peakInputs,pending);peakBytes=max(peakBytes,bytes)
        let submittedAt=ProcessInfo.processInfo.systemUptime
        queue.async { [self] in
            defer {lock.lock();pending-=1;bytes-=cost;lock.unlock()}
            lock.lock();let usable=active && !failed;lock.unlock()
            guard usable else {
                lock.lock();discarded+=1;lock.unlock()
                if let completion {notifications.async {completion(.failure(Failure.aborted))}}
                return
            }
            let startedAt=ProcessInfo.processInfo.systemUptime
            lock.lock();maximumWait=max(maximumWait,startedAt-submittedAt);lock.unlock()
            do {
                switch input {
                case .sample(let sample): try store.append(sample:sample)
                case .event(let kind,let fields,let synchronize): try store.appendEvent(kind:kind,fields:fields,synchronize:synchronize)
                }
                lock.lock();written+=1;maximumWrite=max(maximumWrite,ProcessInfo.processInfo.systemUptime-startedAt);lock.unlock()
                if let completion {notifications.async {completion(.success(()))}}
            } catch {
                lock.lock();writeFailures+=1;maximumWrite=max(maximumWrite,ProcessInfo.processInfo.systemUptime-startedAt);lock.unlock()
                reject("recording_write_failed: \(error)")
                if let completion {notifications.async {completion(.failure(error))}}
            }
        }
        lock.unlock()
    }
    private func reject(_ reason: String) {
        lock.lock()
        guard active,!failed else {lock.unlock();return}
        failed=true;active=false;let generation=epoch
        scheduleCleanupLocked()
        notifications.async { [self] in onFailure(generation,reason) }
        lock.unlock()
    }
    private func barrier(_ operation: () throws -> Void) throws {
        // Rejected controls must not wait behind an already stalled writer.
        lock.lock();let admitted=active && !failed;lock.unlock()
        guard admitted else {throw Failure.aborted}
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
            let stats=statistics
            try store.appendEvent(kind:"writer_statistics",fields:[
                "schema":"eeg.writer-statistics.v1","generation":String(stats.generation),
                "maximum_pending_inputs":String(capacity),"maximum_pending_payload_bytes":String(byteCapacity),
                "admitted_inputs":String(stats.admittedInputs),"written_inputs":String(stats.writtenInputs),
                "discarded_inputs":String(stats.discardedInputs),"failed_writes":String(stats.failedWrites),
                "peak_pending_inputs":String(stats.peakPendingInputs),"peak_pending_payload_bytes":String(stats.peakPendingPayloadBytes),
                "maximum_queue_wait_seconds":String(stats.maximumQueueWaitSeconds),"maximum_write_seconds":String(stats.maximumWriteSeconds),
                "timing_basis":"process_monotonic","scope":"asynchronous_inputs_only"])
            try store.finish()
            lock.lock();active=false;lock.unlock()
        }
    }
    /// Stop accepting input immediately. In-flight I/O cannot be cancelled; cleanup
    /// completes on the writer queue and remains visible in statistics meanwhile.
    /// start() rejects while cleanup is pending instead of waiting for the disk.
    public func abort() {
        lock.lock();active=false
        scheduleCleanupLocked()
        lock.unlock()
    }
    private func scheduleCleanupLocked() {
        guard !cleanupPending else {return}
        cleanupPending=true
        queue.async { [self] in
            store.abort()
            lock.lock();cleanupPending=false;lock.unlock()
        }
    }
}
