import Foundation
import Darwin

/// Local profile library. Listing is metadata only; selecting always validates bytes.
public struct EEGProfileStore: Sendable {
    public struct Entry: Identifiable, Sendable {
        public let id: String
        public let modified: Date
        public let bytes: Int
    }
    public enum Failure: Error { case invalidIdentifier, invalidFile, oversized, identityMismatch }
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    private func path(_ id: String) throws -> URL {
        guard directory.isFileURL, id.count == 64,
              id.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw Failure.invalidIdentifier }
        return directory.appendingPathComponent(id + ".json")
    }
    public func entries() throws -> [Entry] {
        guard directory.isFileURL else { throw Failure.invalidFile }
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).compactMap { url in
            guard url.pathExtension == "json" else { return nil }
            let id = url.deletingPathExtension().lastPathComponent
            _ = try path(id)
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attrs[.type] as? FileAttributeType == .typeRegular else { throw Failure.invalidFile }
            return Entry(id: id, modified: attrs[.modificationDate] as? Date ?? .distantPast, bytes: (attrs[.size] as? NSNumber)?.intValue ?? 0)
        }.sorted { $0.modified == $1.modified ? $0.id < $1.id : $0.modified > $1.modified }
    }
    public func load(_ id: String) throws -> EEGMentalProfile {
        let profile = try Self.readDocument(try path(id))
        guard profile.id == id else { throw Failure.identityMismatch }
        return profile
    }
    public func save(_ artifact: EEGProfileCreation.Artifact) throws -> EEGMentalProfile {
        let destination = try path(artifact.profile.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try EEGProfileCreation.save(artifact, to: destination)
        // The view receives the persisted, revalidated artifact, not only the fit result.
        return try load(artifact.profile.id)
    }
    public static func readDocument(_ url: URL) throws -> EEGMentalProfile {
        guard url.isFileURL else { throw Failure.invalidFile }
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { throw Failure.invalidFile }
        let limit = 8 * 1024 * 1024
        guard info.st_size <= limit else { throw Failure.oversized }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw Failure.oversized }
        return try EEGMentalProfile.load(data: data)
    }
}
