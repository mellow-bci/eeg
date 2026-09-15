import Foundation
import CoreFoundation
import CryptoKit
import Darwin

public enum EEGProfileCreation {
    public struct Artifact: Sendable {
        public let data: Data
        public let profile: EEGMentalProfile
    }
    public static func train(_ records: [EEGTrainingRecord], participantID: String,
                             settings: ProcessingSettings = ProcessingSettings(), parentProfileID: String? = nil) throws -> Artifact {
        try Task.checkCancellation()
        if let parent = parentProfileID {
            guard parent.count == 64, parent.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw EEGMentalProfile.Failure.provenance }
        }
        let fitted = try EEGMentalTraining.fit(records, participantID: participantID, settings: settings)
        try Task.checkCancellation()
        let encoder = JSONEncoder()
        var object = try JSONSerialization.jsonObject(with: encoder.encode(fitted)) as! [String: Any]
        let encodedRecords = try PythonCompatibleJSON.encode(JSONSerialization.jsonObject(with: encoder.encode(records)))
        var hashes = [String: String]()
        for record in records { hashes[record.session_id] = record.recording_content_sha256 }
        object.merge([
            "schema": "eeg.mental-profile.v2", "profile_id": "", "participant_id": participantID,
            "parent_profile_id": parentProfileID as Any? ?? NSNull(),
            "feature_config_id": EEGMentalFeatures.configurationID,
            "processing_settings": try JSONSerialization.jsonObject(with: settings.jsonData()),
            "design": ["origin": "independent_design_not_recovered_cortex",
                "feature_selection": "training-only between/within variance ratio",
                "selected_features": settings.selectedFeatures, "pca_components": settings.pcaComponents,
                "gaussian": "diagonal_regularized", "variance_floor": settings.varianceFloor,
                "class_prior": "equal", "score_threshold": settings.scoreThreshold,
                "margin_threshold": settings.marginThreshold, "persistence_windows": settings.persistenceWindows,
                "parameters_physiologically_validated": false] as [String: Any],
            "training_sessions": hashes.keys.sorted(), "training_recording_hashes": hashes,
            "training_window_ids": records.map(\.window_id).sorted(),
            "training_records_sha256": SHA256.hash(data: encodedRecords).map { String(format: "%02x", $0) }.joined(),
            "validation_status": "experimental_unvalidated", "system_control_enabled": false
        ]) { _, new in new }
        object["profile_id"] = try ProfileCanonicalJSON.digest(PythonCompatibleJSON.encode(object))
        let data = try PythonCompatibleJSON.encode(object)
        let profile = try EEGMentalProfile.load(data: data)
        try Task.checkCancellation()
        return Artifact(data: data, profile: profile)
    }

    /// Refit with explicit lineage. No previous weights or validation are inherited.
    public static func retrain(_ records: [EEGTrainingRecord], participantID: String,
                               parent: EEGMentalProfile, settings: ProcessingSettings) throws -> Artifact {
        guard participantID == parent.participantID else { throw EEGLabeledEvaluation.Failure.participantMismatch }
        return try train(records, participantID: participantID, settings: settings, parentProfileID: parent.id)
    }

    /// Publishes a fully written private file without replacing an existing profile.
    public static func save(_ artifact: Artifact, to destination: URL) throws {
        try Task.checkCancellation()
        _ = try EEGMentalProfile.load(data: artifact.data)
        guard destination.isFileURL else { throw EEGRecordingError.invalidPath }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".profile-" + UUID().uuidString)
        let fd = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: temporary) }
        try handle.write(contentsOf: artifact.data)
        try handle.synchronize(); try handle.close()
        // Publication is the commit point. Cancellation after it cannot retract a saved profile.
        try Task.checkCancellation()
        guard Darwin.link(temporary.path, destination.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}

/// Serializer for the finite JSON values in independent profile artifacts.
/// ASCII escapes and shortest Double spelling match the Python profile checksum.
/// Interoperability is tested; this is not a general JSON canonicalization standard.
enum PythonCompatibleJSON {
    static func encode(_ value: Any) throws -> Data { Data(try text(value).utf8) }
    private static func quoted(_ string: String) -> String {
        var result = "\""
        for unit in string.utf16 {
            switch unit {
            case 34: result += "\\\""
            case 92: result += "\\\\"
            case 8: result += "\\b"
            case 9: result += "\\t"
            case 10: result += "\\n"
            case 12: result += "\\f"
            case 13: result += "\\r"
            case 32...126: result += String(UnicodeScalar(unit)!)
            default: result += String(format: "\\u%04x", unit)
            }
        }
        return result + "\""
    }
    private static func text(_ value: Any) throws -> String {
        if value is NSNull { return "null" }
        if let string = value as? String { return quoted(string) }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            let type = String(cString: number.objCType)
            if type == "d" || type == "f" {
                guard number.doubleValue.isFinite else { throw EEGMentalProfile.Failure.integrity }
                return String(number.doubleValue)
            }
            return number.stringValue
        }
        if let array = value as? [Any] { return "[" + (try array.map(text)).joined(separator: ",") + "]" }
        if let object = value as? [String: Any] {
            return "{" + (try object.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }.map { quoted($0) + ":" + (try text(object[$0]!)) }).joined(separator: ",") + "}"
        }
        throw EEGMentalProfile.Failure.integrity
    }
}
