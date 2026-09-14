import Foundation
import Darwin

public struct ProcessingSettings: Codable, Equatable, Sendable {
    public static let schemaVersion = "eeg.processing-settings.v1"
    public var schema = schemaVersion
    public var maxTrainingWindows: Int? = nil
    public var selectedFeatures = 20
    public var pcaComponents = 8
    public var varianceFloor = 0.05
    public var scoreThreshold = 0.9
    public var marginThreshold = 0.25
    public var persistenceWindows = 2
    public init() {}

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schema
        case maxTrainingWindows = "max_training_windows"
        case selectedFeatures = "selected_features"
        case pcaComponents = "pca_components"
        case varianceFloor = "variance_floor"
        case scoreThreshold = "score_threshold"
        case marginThreshold = "margin_threshold"
        case persistenceWindows = "persistence_windows"
    }
    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    public init(from decoder: Decoder) throws {
        self.init()
        let all = try decoder.container(keyedBy: AnyKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.rawValue))
        guard all.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw ProcessingSettingsError.invalid("Unknown processing setting.")
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if values.contains(.schema) { schema = try values.decode(String.self, forKey: .schema) }
        maxTrainingWindows = try values.decodeIfPresent(Int.self, forKey: .maxTrainingWindows)
        if values.contains(.selectedFeatures) { selectedFeatures = try values.decode(Int.self, forKey: .selectedFeatures) }
        if values.contains(.pcaComponents) { pcaComponents = try values.decode(Int.self, forKey: .pcaComponents) }
        if values.contains(.varianceFloor) { varianceFloor = try values.decode(Double.self, forKey: .varianceFloor) }
        if values.contains(.scoreThreshold) { scoreThreshold = try values.decode(Double.self, forKey: .scoreThreshold) }
        if values.contains(.marginThreshold) { marginThreshold = try values.decode(Double.self, forKey: .marginThreshold) }
        if values.contains(.persistenceWindows) { persistenceWindows = try values.decode(Int.self, forKey: .persistenceWindows) }
        try validate()
    }
    public func encode(to encoder: Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schema, forKey: .schema)
        // Emit explicit null, matching the CLI's no-cap default.
        try values.encode(maxTrainingWindows, forKey: .maxTrainingWindows)
        try values.encode(selectedFeatures, forKey: .selectedFeatures)
        try values.encode(pcaComponents, forKey: .pcaComponents)
        try values.encode(varianceFloor, forKey: .varianceFloor)
        try values.encode(scoreThreshold, forKey: .scoreThreshold)
        try values.encode(marginThreshold, forKey: .marginThreshold)
        try values.encode(persistenceWindows, forKey: .persistenceWindows)
    }
    public func validate() throws {
        guard schema == Self.schemaVersion else { throw ProcessingSettingsError.invalid("Unsupported settings version.") }
        guard (1...70).contains(selectedFeatures) else { throw ProcessingSettingsError.invalid("Select between 1 and 70 features.") }
        guard (1...selectedFeatures).contains(pcaComponents) else { throw ProcessingSettingsError.invalid("PCA components must be between 1 and the selected feature count.") }
        guard persistenceWindows >= 1 else { throw ProcessingSettingsError.invalid("Persistence must be at least one window.") }
        if let budget = maxTrainingWindows, budget < 1 { throw ProcessingSettingsError.invalid("An optional training budget must be positive.") }
        guard varianceFloor.isFinite, varianceFloor > 0 else { throw ProcessingSettingsError.invalid("Variance floor must be a finite positive number.") }
        guard scoreThreshold.isFinite, scoreThreshold > 0, scoreThreshold <= 1 else { throw ProcessingSettingsError.invalid("Score threshold must be greater than zero and no greater than one.") }
        guard marginThreshold.isFinite, marginThreshold >= 0, marginThreshold <= 1 else { throw ProcessingSettingsError.invalid("Margin threshold must be between zero and one.") }
    }
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

public enum ProcessingSettingsError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

/// One local settings file; saving never changes or silently retrains an existing profile.
public final class ProcessingSettingsStore {
    public let file: URL
    public static let maximumBytes = 65536
    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw ProcessingSettingsError.invalid("Settings directory must be a directory, not a link.") }
        file = directory.appendingPathComponent("processing-settings.json")
    }
    public func load() throws -> ProcessingSettings {
        do { return try Self.read(file) }
        catch let error as POSIXError where error.code == .ENOENT { return ProcessingSettings() }
    }
    public static func read(_ url: URL) throws -> ProcessingSettings {
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size > 0, info.st_size <= maximumBytes else { throw ProcessingSettingsError.invalid("Choose a settings JSON file up to 64 KiB.") }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw ProcessingSettingsError.invalid("Settings file is too large.") }
        return try JSONDecoder().decode(ProcessingSettings.self, from: data)
    }
    public func save(_ settings: ProcessingSettings) throws {
        let data = try settings.jsonData()
        let temporary = file.deletingLastPathComponent().appendingPathComponent(".settings-" + UUID().uuidString + ".tmp")
        let fd = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: temporary) }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        guard Darwin.rename(temporary.path, file.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
