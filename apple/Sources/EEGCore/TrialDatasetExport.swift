import Foundation

/// Builds the canonical dataset only from recovered, planned trial evidence.
public enum EEGTrialDatasetExport {
    public enum Split: String, Sendable { case train, evaluation }
    public struct Source: Sendable {
        public let recording: URL
        public let split: Split
        public let independenceDeclaration: String
        public init(recording: URL, split: Split, independenceDeclaration: String) {
            self.recording=recording;self.split=split;self.independenceDeclaration=independenceDeclaration
        }
    }
    public enum Failure: Error { case controlTraining, missingDeclaration, noAcceptedTrials, participantMismatch, noUsableWindows }
    public static func manifest(sources: [Source], store: EEGRecordingStore,
                                settings: ProcessingSettings = ProcessingSettings()) throws -> Data {
        try settings.validate()
        guard !sources.isEmpty else { throw Failure.noAcceptedTrials }
        var participant: String?,sessions: [[String:Any]]=[]
        for source in sources {
            guard !source.independenceDeclaration.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw Failure.missingDeclaration }
            let recovered=try store.recoverTrialRecording(recording:source.recording)
            guard let first=recovered.trials.first else { throw Failure.noAcceptedTrials }
            if let participant,participant != first.participantID { throw Failure.participantMismatch }
            participant=first.participantID
            guard source.split != .train || !recovered.trials.contains(where: { $0.isControl }) else { throw Failure.controlTraining }
            let accepted=try recovered.trials.filter { $0.phase == .reviewed && $0.accepted }.map {
                try JSONSerialization.jsonObject(with:JSONEncoder().encode($0.datasetTrial()))
            }
            guard !accepted.isEmpty else { throw Failure.noAcceptedTrials }
            sessions.append(["id":first.sessionID,"split":source.split.rawValue,
                "recording":source.recording.lastPathComponent,"file_sha256":recovered.fileSHA256,
                "independent_session":true,"independence_declaration":source.independenceDeclaration,
                "trials":accepted,"evidence_schema":"eeg.trial-evidence.v1",
                "started_trials":recovered.trials.count,"excluded_or_unreviewed_trials":recovered.trials.count-accepted.count])
        }
        let data=try JSONSerialization.data(withJSONObject:["schema":"eeg.dataset.v1","participant_id":participant!,"sessions":sessions],options:[.sortedKeys,.prettyPrinted])
        // One extraction path: checks hashes again, window coverage, overlapping
        // intervals, session identity and duplicate EEG content before returning.
        let dataset=try EEGTrainingDataset.load(data,store:store,settings:settings)
        guard dataset.sessions.allSatisfy({ $0.usableWindows > 0 }) else { throw Failure.noUsableWindows }
        return data
    }
}
