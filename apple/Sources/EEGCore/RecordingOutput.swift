import Foundation

/// Internal I/O boundary for deterministic storage-failure tests. Production
/// always wraps the securely opened local file; no simulated data source exists.
protocol EEGRecordingOutput: AnyObject {
    func write(_ data: Data) throws
    func synchronize() throws
    func close() throws
    func offset() throws -> UInt64
    func truncate(at offset: UInt64) throws
}
final class EEGFileRecordingOutput: EEGRecordingOutput {
    private let file: FileHandle
    init(_ file: FileHandle) { self.file=file }
    func write(_ data: Data) throws { try file.write(contentsOf:data) }
    func synchronize() throws { try file.synchronize() }
    func close() throws { try file.close() }
    func offset() throws -> UInt64 { try file.offset() }
    func truncate(at offset: UInt64) throws { try file.truncate(atOffset:offset) }
}
