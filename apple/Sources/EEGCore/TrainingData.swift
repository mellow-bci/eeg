import Foundation

/// Explicitly accepted feature records. These declarations do not prove physiology;
/// the recording/label workflow must establish their provenance before construction.
public struct EEGTrainingRecord: Codable, Sendable {
    public let accepted: Bool
    public let label_verified: Bool
    public let artifact_flags: [String]
    public let usable: Bool
    public let feature_config_id: String
    public let participant_id: String
    public let window_id: String
    public let session_id: String
    public let label: String
    public let recording_content_sha256: String
    public let values: [Double]
}

public struct EEGPreparedTraining: Sendable {
    public let classes: [String]
    public let labels: [Int]
    public let center: [Double]
    public let scale: [Double]
    public let selected: [Int]
    public let pcaMean: [Double]
    public let centeredSelected: [[Double]]
    public let recordingHashes: [String: String]
    public let windowIDs: [String]
}

public enum EEGTrainingData {
    public enum Failure: Error { case invalidRecords, unverifiedLabels, invalidFeatures, duplicateWindows, sessionProvenance, insufficientClasses, insufficientClassSessions, resourceLimit, numericalFailure }

    /// Same independent recipe as processing.mental.train through PCA input.
    /// Fits normalization and Fisher-style feature ranking on training records only.
    public static func prepare(_ records: [EEGTrainingRecord], participantID: String,
                               settings: ProcessingSettings = ProcessingSettings()) throws -> EEGPreparedTraining {
        try Task.checkCancellation()
        try settings.validate()
        guard !participantID.isEmpty, !records.isEmpty else { throw Failure.invalidRecords }
        if let limit = settings.maxTrainingWindows, records.count > limit { throw Failure.resourceLimit }
        var hashes = [String: String](), ids = Set<String>()
        for record in records {
            try Task.checkCancellation()
            guard record.accepted, record.label_verified else { throw Failure.unverifiedLabels }
            guard record.participant_id == participantID, !record.label.isEmpty, !record.session_id.isEmpty,
                  !record.window_id.isEmpty else { throw Failure.invalidRecords }
            guard record.usable, record.artifact_flags.isEmpty, record.feature_config_id == EEGMentalFeatures.configurationID,
                  record.values.count == 70, record.values.allSatisfy(\.isFinite) else { throw Failure.invalidFeatures }
            guard ids.insert(record.window_id).inserted else { throw Failure.duplicateWindows }
            let hash = record.recording_content_sha256
            guard hash.count == 64, hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  hashes[record.session_id] == nil || hashes[record.session_id] == hash else { throw Failure.sessionProvenance }
            hashes[record.session_id] = hash
        }
        guard hashes.count >= 2, Set(hashes.values).count == hashes.count else { throw Failure.sessionProvenance }
        let classes = Set(records.map(\.label)).sorted()
        guard classes.count >= 2, classes.contains("neutral") else { throw Failure.insufficientClasses }
        let grouped = classes.map { label in records.indices.filter { records[$0].label == label } }
        for indices in grouped {
            guard indices.count >= 20, Set(indices.map { records[$0].session_id }).count >= 2 else { throw Failure.insufficientClassSessions }
        }
        let n = Double(records.count)
        let center = (0..<70).map { j in records.reduce(0.0) { $0 + $1.values[j] } / n }
        let scale = (0..<70).map { j -> Double in
            let sd = sqrt(records.reduce(0.0) { $0 + pow($1.values[j] - center[j], 2) } / n)
            return sd < 1e-8 ? 1 : sd
        }
        let normalized = try records.map { record in
            try Task.checkCancellation()
            return (0..<70).map { (record.values[$0] - center[$0]) / scale[$0] }
        }
        let means = grouped.map { indices in (0..<70).map { j in indices.reduce(0.0) { $0 + normalized[$1][j] } / Double(indices.count) } }
        let ratio = try (0..<70).map { j -> Double in
            try Task.checkCancellation()
            let mean = means.reduce(0.0) { $0 + $1[j] } / Double(classes.count)
            let between = means.reduce(0.0) { $0 + pow($1[j] - mean, 2) } / Double(classes.count)
            let within = grouped.indices.reduce(0.0) { total, c in
                total + grouped[c].reduce(0.0) { $0 + pow(normalized[$1][j] - means[c][j], 2) } / Double(grouped[c].count)
            } / Double(classes.count)
            return between / (within + 1e-6)
        }
        guard (center + scale + ratio).allSatisfy(\.isFinite), normalized.allSatisfy({ $0.allSatisfy(\.isFinite) }) else { throw Failure.numericalFailure }
        let selected = Array((0..<70).sorted { ratio[$0] == ratio[$1] ? $0 < $1 : ratio[$0] > ratio[$1] }.prefix(settings.selectedFeatures))
        let pcaMean = selected.map { j in normalized.reduce(0.0) { $0 + $1[j] } / n }
        let centered = normalized.map { row in selected.enumerated().map { row[$0.element] - pcaMean[$0.offset] } }
        try Task.checkCancellation()
        return EEGPreparedTraining(classes: classes, labels: records.map { classes.firstIndex(of: $0.label)! },
            center: center, scale: scale, selected: selected, pcaMean: pcaMean, centeredSelected: centered,
            recordingHashes: hashes, windowIDs: records.map(\.window_id))
    }
}
