import Foundation

/// Verifies recorded shadow outputs, not intent accuracy or source authenticity.
public enum EEGShadowVerification {
    public enum Failure: Error { case invalidRun, missingRun, invalidLimit, limitExceeded, trainingContent }
    public struct Report: Sendable {
        public let recordingSHA256: String
        public let runID: String
        public let profileID: String
        public let replayWindows: Int
        public let recordedWindows: Int
        public let mismatchedOrdinals: [Int]
        public let missingOrdinals: [Int]
        public let stopObserved: Bool
        public let stopReason: String?
        public var completeMatch: Bool {stopObserved && ["operator_stopped","recording_stopped","profile_view_closed"].contains(stopReason ?? "") && recordedWindows>0 && mismatchedOrdinals.isEmpty && missingOrdinals.isEmpty}
        public let systemControlEnabled=false
    }
    public struct Run: Identifiable, Sendable {
        public let id: String
        public let sessionID: String
        public let profileID: String
    }
    public struct Catalog: Sendable {
        public let recordingSHA256: String
        public let runs: [Run]
    }
    /// Discovery is metadata only. A listed run still requires full verification.
    public static func catalog(store: EEGRecordingStore, recording: URL, maximumRuns: Int=1024) throws -> Catalog {
        guard maximumRuns>0 else {throw Failure.invalidLimit}
        var runs=[Run](),identifiers=Set<String>()
        let digest=try store.finalizedRecords(recording:recording) {data,sample in
            guard sample == nil else {return}
            guard let object=try JSONSerialization.jsonObject(with:data) as? [String:Any] else {throw Failure.invalidRun}
            guard object["kind"] as? String=="shadow_start" else {return}
            guard runs.count<maximumRuns else {throw Failure.limitExceeded}
            guard let id=object["shadow_run_id"] as? String,let session=object["session_id"] as? String,
                  let profile=object["profile_id"] as? String,
                  [id,session,profile].allSatisfy({!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && $0.utf8.count<=4096}),
                  identifiers.insert(id).inserted else {throw Failure.invalidRun}
            runs.append(Run(id:id,sessionID:session,profileID:profile))
        }
        return Catalog(recordingSHA256:digest,runs:runs)
    }
    /// Start the same assembler/detector at the recorded run boundary, rather
    /// than comparing against differently aligned whole-recording windows.
    public static func run(store: EEGRecordingStore, recording: URL, profile: EEGMentalProfile,
                           runID: String, maximumWindows: Int=10000, expectedRecordingSHA256: String?=nil) throws -> Report {
        guard !runID.isEmpty else {throw Failure.invalidRun}
        guard maximumWindows>0 else {throw Failure.invalidLimit}
        var metadata: Data?
        var started=false, active=false, stopped=false
        var sessionID: String?
        var stopReason: String?
        var assembler=EEGAnalysisWindowAssembler()
        var processor: EEGWindowInference?
        var expected=[EEGWindowInferenceResult]()
        var seen=Set<Int>(),mismatches=[Int]()
        var lastRecordedOrdinal = -1
        var fingerprint=EEGRecordingFingerprint()
        let digest=try store.finalizedRecords(recording:recording) {data,sample in
            if let sample {
                try fingerprint.append(sample)
                if active,let window=assembler.append(sample) {
                    guard expected.count<maximumWindows else {throw Failure.limitExceeded}
                    expected.append(processor!.process(window))
                }
                return
            }
            guard let object=try JSONSerialization.jsonObject(with:data) as? [String:Any] else {throw Failure.invalidRun}
            let kind=object["kind"] as? String
            if kind=="device_metadata" {metadata=data;return}
            guard object["shadow_run_id"] as? String==runID else {return}
            switch kind {
            case "shadow_start":
                guard !started,let metadata,
                      object["profile_id"] as? String==profile.id,
                      object["participant_id"] as? String==profile.participantID,
                      object["feature_config_id"] as? String==EEGMentalFeatures.configurationID,
                      object["system_control_enabled"] as? String=="false",
                      let session=object["session_id"] as? String,
                      !profile.trainingSessions.contains(session) else {throw Failure.invalidRun}
                processor=try EEGWindowInference(profile:profile,participantID:profile.participantID,sessionID:session)
                try assembler.event(metadata)
                try assembler.event(Data("{\"kind\":\"transport_status\",\"status\":\"stable\"}".utf8))
                sessionID=session;started=true;active=true
            case "shadow_inference":
                guard active,let ordinalText=object["ordinal"] as? String,let ordinal=Int(ordinalText),
                      expected.indices.contains(ordinal),ordinal>lastRecordedOrdinal,seen.insert(ordinal).inserted else {throw Failure.invalidRun}
                lastRecordedOrdinal=ordinal
                let row=expected[ordinal]
                let matches = object["session_id"] as? String==sessionID &&
                    object["profile_id"] as? String==profile.id &&
                    object["feature_config_id"] as? String==EEGMentalFeatures.configurationID &&
                    object["generation"] as? String=="0" &&
                    object["status"] as? String==row.status &&
                    object["system_control_enabled"] as? String=="false" &&
                    object["candidate"] as? String==(row.candidate ?? "") &&
                    object["has_candidate"] as? String==String(row.candidate != nil) &&
                    object["reasons"] as? String==row.reasons.joined(separator:";") &&
                    object["first_sample_index"] as? String==row.firstSampleIndex.map(String.init) &&
                    object["last_sample_index"] as? String==row.lastSampleIndex.map(String.init) &&
                    object["sample_count"] as? String==String(row.sampleCount) &&
                    (object["input_start"] as? String).flatMap(Double.init)==row.inputStart &&
                    (object["input_end"] as? String).flatMap(Double.init)==row.inputEnd &&
                    object["time_basis"] as? String=="recorded_receipt_seconds"
                if !matches {mismatches.append(ordinal)}
            case "shadow_stop":
                guard active,let reason=object["reason"] as? String,!reason.isEmpty else {throw Failure.invalidRun}
                stopReason=reason;stopped=true;active=false
            default:throw Failure.invalidRun
            }
        }
        if let expectedRecordingSHA256,expectedRecordingSHA256 != digest {throw EEGRecordingError.sourceChanged}
        guard started else {throw Failure.missingRun}
        guard !profile.trainingRecordingHashes.values.contains(try fingerprint.finalize()) else {throw Failure.trainingContent}
        return Report(recordingSHA256:digest,runID:runID,profileID:profile.id,replayWindows:expected.count,
            recordedWindows:seen.count,mismatchedOrdinals:mismatches.sorted(),
            missingOrdinals:expected.indices.filter {!seen.contains($0)},stopObserved:stopped,stopReason:stopReason)
    }
}
