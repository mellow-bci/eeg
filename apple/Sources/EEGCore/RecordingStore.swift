import Foundation
import Darwin
import CoreFoundation
import CryptoKit

public struct EEGRecordingInfo: Identifiable, Sendable {
    public let url: URL
    public var id: String { url.lastPathComponent }
    public var name: String { url.lastPathComponent }
    public let sampleCount: Int
    public let complete: Bool
    public let corrupt: Bool
    public init(url:URL,sampleCount:Int,complete:Bool,corrupt:Bool) {self.url=url;self.sampleCount=sampleCount;self.complete=complete;self.corrupt=corrupt}
}

public enum EEGRecordingError: Error, LocalizedError {
    case invalidPath, alreadyRecording, notRecording, invalidData, unavailableUnits, lineTooLarge, sourceChanged
    public var errorDescription: String? {
        switch self {
        case .invalidPath: return "Recording path is not a regular private recording file."
        case .alreadyRecording: return "A recording is already active."
        case .notRecording: return "No recording is active."
        case .invalidData: return "Recording contains invalid or incomplete data."
        case .unavailableUnits: return "Calibrated microvolts are unavailable in this recording."
        case .lineTooLarge: return "Recording event exceeds the supported size."
        case .sourceChanged: return "Recording changed during reading. Retry with a completed, unchanged source."
        }
    }
}

/// Local append-only recording storage. No cloud, account or device entitlement dependency.
/// Serialize calls through the lock; do not execute file I/O on a real-time audio thread.
public final class EEGRecordingStore {
    public enum ExportFormat: String, Sendable { case native, csv }
    public enum Units: String, Sendable { case adc, microvolts }
    public let directory: URL
    private let lock = NSLock()
    private var writer: EEGRecordingOutput?
    var outputFactory: (FileHandle) -> EEGRecordingOutput = { EEGFileRecordingOutput($0) }
    private var recordingID: String?
    private var trialEvidence: [String: EEGTrialEvidence] = [:]
    private var count = 0
    private let encoder = JSONEncoder()
    private static let maximumLine = 4 * 1024 * 1024
    public static let channels = ["AF3", "F7", "F3", "FC5", "T7", "P7", "O1", "O2", "P8", "T8", "FC6", "F4", "F8", "AF4"]
    private struct SampleEvent: Codable { let kind: String; let sample: EEGSample }

    public init(directory: URL) throws {
        self.directory = directory.standardizedFileURL
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let attributes = try FileManager.default.attributesOfItem(atPath: self.directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw EEGRecordingError.invalidPath }
    }

    deinit { try? writer?.close() }

    @discardableResult public func start() throws -> URL {
        lock.lock(); defer { lock.unlock() }
        guard writer == nil else { throw EEGRecordingError.alreadyRecording }
        let url = directory.appendingPathComponent(UUID().uuidString.lowercased() + ".jsonl")
        let handle = outputFactory(try Self.open(url, writing: true))
        writer = handle; count = 0; recordingID = url.lastPathComponent; trialEvidence = [:]
        do {
            try writeEvent(["kind": "stream_start", "schema": "eeg-native-v1", "time": ISO8601DateFormatter().string(from: Date())])
        } catch { try? handle.close(); writer = nil; throw error }
        return url
    }

    public func append(sample: EEGSample) throws {
        lock.lock(); defer { lock.unlock() }
        guard let handle = writer else { throw EEGRecordingError.notRecording }
        try Self.validateSample(sample)
        var data = try encoder.encode(SampleEvent(kind: "eeg_sample", sample: sample))
        guard data.count < Self.maximumLine else { throw EEGRecordingError.lineTooLarge }
        data.append(0x0a)
        do { try handle.write(data); count += 1 }
        catch { abortLocked(); throw error }
    }

    public func appendEvent(kind: String, fields: [String: String], synchronize: Bool = false) throws {
        lock.lock(); defer { lock.unlock() }
        guard !kind.isEmpty, kind != "summary", kind != "stream_start", kind != "eeg_sample", kind != "trial_evidence", fields["kind"] == nil else { throw EEGRecordingError.invalidData }
        var event: [String: Any] = fields
        event["kind"] = kind
        do {
            try writeEvent(event)
            if synchronize {try writer?.synchronize()}
        } catch { abortLocked(); throw error }
    }

    /// Persist each trial transition alongside original samples. Call from a file-I/O
    /// executor, not an audio callback. Success means write + filesystem synchronize
    /// returned; it is not a hardware power-loss guarantee.
    public func appendTrialEvidence(_ trial: EEGTrialEvidence) throws {
        lock.lock(); defer { lock.unlock() }
        guard let handle = writer, let recordingID else { throw EEGRecordingError.notRecording }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try trial.validateRevision(after: trialEvidence[trial.id])
        let object = try JSONSerialization.jsonObject(with: encoder.encode(trial))
        do {
            try writeEvent(["kind": "trial_evidence", "recording_id": recordingID,
                            "sample_count_at_write": count, "revision": trial.events.count, "evidence": object])
            try handle.synchronize()
            trialEvidence[trial.id] = trial
        } catch {
            // A write may have partially succeeded. Never append a completion marker
            // to a stream whose evidence persistence is uncertain.
            try? handle.close(); writer = nil; self.recordingID = nil
            throw error
        }
    }

    /// Recover all trial revisions from a finalized, unchanged recording. This
    /// validates lifecycle evidence, not physiological truth or source authenticity.
    public struct TrialRecordingEvidence: Sendable {
        public let trials: [EEGTrialEvidence]
        public let fileSHA256: String
    }
    public func recoveredTrials(recording: URL) throws -> [EEGTrialEvidence] {
        try recoverTrialRecording(recording:recording).trials
    }
    public func recoverTrialRecording(recording: URL) throws -> TrialRecordingEvidence {
        try validate(recording)
        var validation = StreamValidation()
        var history: [String:EEGTrialEvidence] = [:], order: [String] = []
        var samples = 0
        var plan: EEGTrialPlan?
        let hash = try Self.lines(recording) { data in
            if try validation.consume(data) != nil { samples += 1 }
            guard let object=try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw EEGRecordingError.invalidData }
            if object["kind"] as? String == "trial_plan" {
                guard plan == nil,order.isEmpty,let json=object["json"] as? String else { throw EEGRecordingError.invalidData }
                plan=try EEGTrialPlan.recover(Data(json.utf8));return
            }
            guard object["kind"] as? String == "trial_evidence" else { return }
            guard let plan else { throw EEGRecordingError.invalidData }
            guard object["recording_id"] as? String == recording.lastPathComponent,
                  object["sample_count_at_write"] as? Int == samples,
                  let raw=object["evidence"] else { throw EEGRecordingError.invalidData }
            let trial=try EEGTrialEvidence.recover(JSONSerialization.data(withJSONObject:raw))
            guard object["revision"] as? Int == trial.events.count else { throw EEGRecordingError.invalidData }
            try trial.validateRevision(after:history[trial.id])
            if history[trial.id] == nil {
                guard order.count < plan.trials.count else { throw EEGRecordingError.invalidData }
                let expected=plan.trials[order.count]
                guard trial.id == expected.id,trial.sessionID == expected.sessionID,
                      trial.participantID == expected.participantID,trial.requestedCondition == expected.requestedCondition,
                      trial.startingNumber == expected.startingNumber else { throw EEGRecordingError.invalidData }
                if let last=order.last,let previous=history[last] {
                    guard previous.phase == .reviewed || previous.phase == .interrupted else { throw EEGRecordingError.invalidData }
                }
                order.append(trial.id)
            }
            guard order.last == trial.id else { throw EEGRecordingError.invalidData }
            if trial.phase == .cueRequested,let at=trial.events.last?.at {
                let previous=order.count > 1 ? history[order[order.count-2]] : nil
                _ = try plan.next(after:previous,started:order.count-1,at:at)
            }
            history[trial.id]=trial
        }
        try validation.finish()
        guard validation.summarized,plan != nil else { throw EEGRecordingError.invalidData }
        return TrialRecordingEvidence(trials:order.compactMap { history[$0] },fileSHA256:hash)
    }

    public func replay(recording: URL, offset: Int = 0, limit: Int = 1280) throws -> [EEGSample] {
        guard offset >= 0, limit > 0, limit <= 10000 else { throw EEGRecordingError.invalidData }
        try validate(recording)
        var result: [EEGSample] = []; var index = 0
        var validation = StreamValidation()
        // Validate the complete snapshot even when the requested page is already full.
        try Self.lines(recording) { data in
            if let sample = try validation.consume(data) {
                if index >= offset && result.count < limit { result.append(sample) }
                index += 1
            }
        }
        try validation.finish()
        return result
    }

    /// Stream analysis windows from a finalized recording using the same schema
    /// validator and bounded line reader as replay. Callback output is provisional
    /// until this method succeeds; callers must discard it if any read fails.
    @discardableResult public func analysisWindows(recording: URL, consume: (EEGAnalysisWindow) throws -> Void) throws -> String {
        try validate(recording)
        var validation = StreamValidation()
        var assembler = EEGAnalysisWindowAssembler()
        let digest = try Self.lines(recording) { data in
            let sample = try validation.consume(data)
            try assembler.event(data)
            if let sample, let window = assembler.append(sample) { try consume(window) }
        }
        try validation.finish()
        guard validation.summarized else { throw EEGRecordingError.invalidData }
        if let tail = assembler.finish() { try consume(tail) }
        return digest
    }

    /// Canonical validated record traversal. Outputs remain provisional until
    /// the complete finalized source passes validation and source-change checks.
    @discardableResult func finalizedRecords(recording: URL, consume: (Data, EEGSample?) throws -> Void) throws -> String {
        try validate(recording)
        var validation=StreamValidation()
        let digest=try Self.lines(recording) { data in
            try consume(data,validation.consume(data))
        }
        try validation.finish()
        guard validation.summarized else {throw EEGRecordingError.invalidData}
        return digest
    }

    /// Close without a completion summary after a failed or cancelled acquisition.
    /// Existing bytes remain available for inspection; this is not a completed dataset.
    public func abort() {
        lock.lock(); defer { lock.unlock() }
        abortLocked()
    }
    private func abortLocked() {
        try? writer?.close()
        writer = nil; recordingID = nil; trialEvidence = [:]
    }

    public func finish() throws {
        lock.lock(); defer { lock.unlock() }
        guard let handle = writer else { throw EEGRecordingError.notRecording }
        defer { writer = nil; recordingID = nil; try? handle.close() }
        let boundary = try handle.offset()
        do {
            try writeEvent(["kind": "summary", "samples": count])
            try handle.synchronize()
        } catch {
            // Remove even a partially written completion marker. Rollback can
            // itself fail on damaged/unavailable storage; preserve both errors.
            let original=error
            do { try handle.truncate(at:boundary);try handle.synchronize() }
            catch { throw EEGRecordingCompletionFailure(original:String(describing:original),rollback:String(describing:error)) }
            throw original
        }
        try handle.close()
    }

    private func writeEvent(_ object: [String: Any]) throws {
        guard let handle = writer else { throw EEGRecordingError.notRecording }
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard data.count < Self.maximumLine else { throw EEGRecordingError.lineTooLarge }
        data.append(0x0a)
        try handle.write(data)
    }

    public func inventory() throws -> [EEGRecordingInfo] {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return urls.filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { url in
            var validation = StreamValidation(); var corrupt = false
            do {
                try validate(url)
                try Self.lines(url) { _ = try validation.consume($0) }
                try validation.finish()
            } catch { corrupt = true }
            return EEGRecordingInfo(url: url, sampleCount: validation.samples,
                                    complete: validation.summarized && !corrupt, corrupt: corrupt)
        }
    }

    /// Byte-preserving native export, including markers and trial evidence.
    /// Well-formed incomplete recordings remain incomplete; no summary is added.
    public func exportNative(recording: URL, to destination: URL) throws {
        try validate(recording)
        _ = try Self.copyNative(recording: recording, to: destination)
    }
    /// Import preserves the archive identity and refuses to overwrite a local file.
    public func importNative(_ source: URL) throws -> EEGRecordingInfo {
        guard source.isFileURL, source.pathExtension == "jsonl", source.lastPathComponent != ".jsonl" else { throw EEGRecordingError.invalidPath }
        return try Self.copyNative(recording: source, to: directory.appendingPathComponent(source.lastPathComponent))
    }
    private static func copyNative(recording: URL, to destination: URL) throws -> EEGRecordingInfo {
        let output = try Self.open(destination, writing: true)
        var succeeded = false
        defer { try? output.close(); if !succeeded { try? FileManager.default.removeItem(at: destination) } }
        var validation = StreamValidation()
        try Self.lines(recording) { data in
            _ = try validation.consume(data)
            var line = data; line.append(0x0a)
            try output.write(contentsOf: line)
        }
        try validation.finish()
        try output.synchronize(); try output.close(); succeeded = true
        return EEGRecordingInfo(url: destination, sampleCount: validation.samples, complete: validation.summarized, corrupt: false)
    }

    /// Destination is created exclusively with 0600 permissions. Any failed export is removed.
    public func exportCSV(recording: URL, to destination: URL, units: Units = .adc) throws {
        try validate(recording)
        let output = try Self.open(destination, writing: true)
        var succeeded = false
        defer { try? output.close(); if !succeeded { try? FileManager.default.removeItem(at: destination) } }
        try output.write(contentsOf: Data((["index", "counter", "received_at", "continuous", "units"] + Self.channels).joined(separator: ",").appending("\n").utf8))
        var validation = StreamValidation()
        try Self.lines(recording) { data in
            guard let sample = try validation.consume(data) else { return }
            let values: [String: Double]
            switch units {
            case .adc: values = sample.electrodesADC
            case .microvolts:
                guard let calibrated = sample.electrodesMicrovolts else { throw EEGRecordingError.unavailableUnits }
                values = calibrated
            }
            guard sample.receivedAt.isFinite, Self.channels.allSatisfy({ values[$0]?.isFinite == true }) else { throw EEGRecordingError.invalidData }
            let row = [String(sample.index), String(sample.counter), String(sample.receivedAt), sample.continuous ? "true" : "false", units.rawValue]
                + Self.channels.map { String(values[$0]!) }
            try output.write(contentsOf: Data(row.joined(separator: ",").appending("\n").utf8))
        }
        try validation.finish()
        try output.synchronize(); try output.close(); succeeded = true
    }

    /// All readers use the same schema and sample checks, including events after a page.
    private struct StreamValidation {
        var samples = 0
        var started = false
        var summarized = false
        mutating func consume(_ data: Data) throws -> EEGSample? {
            guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let kind = event["kind"] as? String, !summarized else { throw EEGRecordingError.invalidData }
            if kind == "stream_start" {
                guard !started, event["schema"] as? String == "eeg-native-v1" else { throw EEGRecordingError.invalidData }
                started = true
                return nil
            }
            guard started else { throw EEGRecordingError.invalidData }
            if kind == "eeg_sample" {
                let sample = try JSONDecoder().decode(SampleEvent.self, from: data).sample
                try EEGRecordingStore.validateSample(sample)
                samples += 1
                return sample
            }
            if kind == "summary" {
                guard let reported = event["samples"] as? NSNumber,
                      CFGetTypeID(reported) != CFBooleanGetTypeID(),
                      reported.doubleValue == Double(samples) else { throw EEGRecordingError.invalidData }
                summarized = true
            } else if kind == "import_failed" { throw EEGRecordingError.invalidData }
            return nil
        }
        func finish() throws {
            // A well-formed unfinished capture remains reviewable, but never marked complete.
            guard started else { throw EEGRecordingError.invalidData }
        }
    }

    static func validateSample(_ sample: EEGSample) throws {
        guard sample.adcWords.count == 15, sample.index >= 0, (0..<128).contains(sample.counter),
              sample.receivedAt.isFinite, channels.allSatisfy({ sample.electrodesADC[$0]?.isFinite == true }) else { throw EEGRecordingError.invalidData }
        if let volts = sample.electrodesMicrovolts {
            guard channels.allSatisfy({ volts[$0]?.isFinite == true }) else { throw EEGRecordingError.invalidData }
        }
    }

    private func validate(_ url: URL) throws {
        guard url.isFileURL, url.standardizedFileURL.deletingLastPathComponent().path == directory.path,
              url.pathExtension == "jsonl", url.lastPathComponent != ".jsonl" else { throw EEGRecordingError.invalidPath }
    }

    private static func open(_ url: URL, writing: Bool) throws -> FileHandle {
        let flags = writing ? O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW : O_RDONLY | O_NOFOLLOW | O_NONBLOCK
        let descriptor = Darwin.open(url.path, flags, mode_t(0o600))
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            Darwin.close(descriptor); throw EEGRecordingError.invalidPath
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    /// Detects ordinary concurrent edits; not a lock or tamper-proof snapshot.
    private struct ReadStamp: Equatable {
        let device: dev_t, inode: ino_t, size: off_t
        let modifiedSeconds: Int, modifiedNanos: Int, changedSeconds: Int, changedNanos: Int
        init(descriptor: Int32) throws {
            var info = stat()
            guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
                  info.st_size >= 0 else { throw EEGRecordingError.invalidData }
            device = info.st_dev; inode = info.st_ino; size = info.st_size
            modifiedSeconds = info.st_mtimespec.tv_sec; modifiedNanos = info.st_mtimespec.tv_nsec
            changedSeconds = info.st_ctimespec.tv_sec; changedNanos = info.st_ctimespec.tv_nsec
        }
    }

    @discardableResult private static func lines(_ url: URL, body: (Data) throws -> Void) throws -> String {
        let handle = try open(url, writing: false); defer { try? handle.close() }
        let initial = try ReadStamp(descriptor: handle.fileDescriptor)
        var remaining = UInt64(initial.size)
        var buffer = Data()
        var digest = SHA256()
        while remaining > 0 {
            let chunk = try handle.read(upToCount: Int(min(remaining, 65536))) ?? Data()
            guard !chunk.isEmpty else { throw EEGRecordingError.invalidData }
            remaining -= UInt64(chunk.count); buffer.append(chunk); digest.update(data: chunk)
            while let end = buffer.firstIndex(of: 0x0a) {
                let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
                guard line.count <= maximumLine else { throw EEGRecordingError.lineTooLarge }
                try body(line)
            }
            guard buffer.count <= maximumLine else { throw EEGRecordingError.lineTooLarge }
        }
        guard buffer.isEmpty else { throw EEGRecordingError.invalidData }
        let final = try ReadStamp(descriptor: handle.fileDescriptor)
        var named = stat()
        guard initial == final, lstat(url.path, &named) == 0,
              (named.st_mode & S_IFMT) == S_IFREG,
              named.st_dev == initial.device, named.st_ino == initial.inode else {
            throw EEGRecordingError.sourceChanged
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public struct EEGRecordingCompletionFailure: Error, LocalizedError {
    public let original: String
    public let rollback: String
    public var errorDescription: String? {
        "Recording completion and rollback both failed. Completion status is uncertain; do not use this file for analysis. Write: \(original). Rollback: \(rollback)."
    }
}
