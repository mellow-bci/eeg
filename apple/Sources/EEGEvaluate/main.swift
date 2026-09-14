import Foundation
import Darwin
import EEGCore

let usage = """
Usage: EEGEvaluate --manifest FILE --profile FILE --recordings DIRECTORY [--controls-only]

Evaluates finalized local recordings through the native EEGCore pipeline.
Writes a complete eeg.native-evaluation.v1 JSON receipt to stdout only on success.
Diagnostics go to stderr. Exit 2 means invalid arguments; exit 1 means evaluation failed.
No acquisition, cloud service or system-control output is enabled.
"""

enum ArgumentFailure: Error { case invalid }
func arguments(_ args: [String]) throws -> ([String: String], Bool) {
    var values = [String: String](), controls = false, i = 0
    while i < args.count {
        let key = args[i]
        if key == "--controls-only" {
            guard !controls else { throw ArgumentFailure.invalid }; controls = true; i += 1
        } else {
            guard ["--manifest", "--profile", "--recordings"].contains(key), values[key] == nil,
                  i + 1 < args.count, !args[i + 1].isEmpty, !args[i + 1].hasPrefix("--") else { throw ArgumentFailure.invalid }
            values[key] = args[i + 1]; i += 2
        }
    }
    guard values.count == 3 else { throw ArgumentFailure.invalid }
    return (values, controls)
}
func readManifest(_ url: URL) throws -> Data {
    let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
    guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    defer { try? handle.close() }
    var info = stat()
    let limit = 8 * 1024 * 1024
    guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size <= limit else {
        throw EEGTrainingDataset.Failure.invalidManifest
    }
    let data = try handle.read(upToCount: limit + 1) ?? Data()
    guard data.count <= limit else { throw EEGTrainingDataset.Failure.invalidManifest }
    return data
}
let args = Array(CommandLine.arguments.dropFirst())
if args == ["--help"] { print(usage); exit(0) }
do {
    let (options, controls) = try arguments(args)
    let directory = URL(fileURLWithPath: options["--recordings"]!, isDirectory: true)
    // Do not create a missing source directory for a read-only evaluation.
    let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
    guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw EEGRecordingError.invalidPath }
    let manifest = try readManifest(URL(fileURLWithPath: options["--manifest"]!))
    let profile = try EEGProfileStore.readDocument(URL(fileURLWithPath: options["--profile"]!))
    let artifact = try EEGEvaluationArtifact.run(manifest: manifest,
        store: EEGRecordingStore(directory: directory), profile: profile, controlsOnly: controls)
    try FileHandle.standardOutput.write(contentsOf: artifact.data)
} catch ArgumentFailure.invalid {
    try? FileHandle.standardError.write(contentsOf: Data((usage + "\n").utf8)); exit(2)
} catch {
    try? FileHandle.standardError.write(contentsOf: Data("Evaluation failed: \(error)\n".utf8)); exit(1)
}
