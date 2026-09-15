import Foundation

/// Bounded shadow-only consumer. Raw recording is the host's independent duty.
/// Results arrive on the worker queue. A UI must check generation again when
/// presenting a result, since a reset can occur after callback delivery.
public final class EEGLiveInference {
    public enum Input: Sendable { case sample(EEGSample), event(Data) }
    public struct Output: Sendable {
        public let generation: UInt64
        public let window: EEGWindowInferenceResult?
        public let failure: String?
    }
    public enum Failure: Error { case invalidCapacity }
    private let lock=NSLock()
    private let queue: DispatchQueue
    private let capacity: Int
    private var pending=0
    private var epoch: UInt64=0
    private var closed=false
    // The following state belongs exclusively to queue.
    private var workerEpoch: UInt64=0
    private var assembler=EEGAnalysisWindowAssembler()
    private var processor: EEGWindowInference
    private let deliver: (Output)->Void
    public convenience init(profile: EEGMentalProfile, participantID: String, sessionID: String,
                            maximumPendingInputs: Int=512, deliver: @escaping (Output)->Void) throws {
        try self.init(profile:profile,participantID:participantID,sessionID:sessionID,
            maximumPendingInputs:maximumPendingInputs,queue:DispatchQueue(label:"cloud.autonomy.eeg.inference",qos:.userInitiated),deliver:deliver)
    }
    init(profile: EEGMentalProfile, participantID: String, sessionID: String,
         maximumPendingInputs: Int, queue: DispatchQueue, deliver: @escaping (Output)->Void) throws {
        guard maximumPendingInputs>0 else { throw Failure.invalidCapacity }
        processor=try EEGWindowInference(profile:profile,participantID:participantID,sessionID:sessionID)
        capacity=maximumPendingInputs;self.queue=queue;self.deliver=deliver
    }
    public var generation: UInt64 { lock.lock();defer {lock.unlock()};return epoch }
    public var pendingInputs: Int { lock.lock();defer {lock.unlock()};return pending }
    /// False means input was NOT processed. The host must expose overload and
    /// resend current metadata/stability before resumed windows can become valid.
    @discardableResult public func submit(_ input: Input) -> Bool {
        lock.lock()
        guard !closed else { lock.unlock();return false }
        guard pending<capacity else { epoch &+= 1;lock.unlock();return false }
        let submittedEpoch=epoch;pending+=1
        // Enqueue under the admission lock so concurrent callers preserve order.
        queue.async { [self] in consume(input,generation:submittedEpoch) }
        lock.unlock();return true
    }
    public func reset() { lock.lock();epoch &+= 1;lock.unlock() }
    public func stop() { lock.lock();closed=true;epoch &+= 1;lock.unlock() }
    private func consume(_ input: Input,generation: UInt64) {
        defer { lock.lock();pending-=1;lock.unlock() }
        lock.lock();let current = !closed && generation==epoch;lock.unlock()
        guard current else { return }
        if workerEpoch != generation {
            assembler=EEGAnalysisWindowAssembler();processor.reset();workerEpoch=generation
        }
        let output: Output?
        do {
            switch input {
            case .event(let data):
                guard data.count<=4*1024*1024 else { throw EEGRecordingError.lineTooLarge }
                try assembler.event(data);output=nil
            case .sample(let sample):
                try EEGRecordingStore.validateSample(sample)
                if let window=assembler.append(sample) {
                    output=Output(generation:generation,window:processor.process(window),failure:nil)
                } else { output=nil }
            }
        } catch {
            assembler=EEGAnalysisWindowAssembler();processor.reset()
            output=Output(generation:generation,window:nil,failure:"input_rejected: \(error)")
        }
        lock.lock();let publish = !closed && generation==epoch;lock.unlock()
        if publish,let output { deliver(output) }
    }
}
