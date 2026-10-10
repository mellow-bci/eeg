import Foundation
import CryptoKit
import SQLite3

/// Independent research-profile storage. SQLite transactions and authenticated
/// encryption are our policies, not the Cortex Couchbase/file format.
final class ReferenceLocalProfileStore {
    typealias Codec = ReferenceProfileCodec
    enum Failure: Error, Equatable {
        case invalidInput, closed, database(Int32), incompatibleSchema, conflict
        case corrupt, resourceLimit, committedWithoutAcknowledgement(Int64)
    }
    enum WriteStage { case beforeCommit, afterCommit }
    struct Settings { let classPriors: [Double]; let neutralScale: Double }
    struct Record {
        let metadata: [String: Codec.Value]
        let classifier: Codec.Classifier
        let settings: Settings
        let revision: Int64
        var runtime: ReferenceRuntimeProfile.Runtime {
            get throws { try ReferenceRuntimeProfile.runtime(classifier,
                classPriors: settings.classPriors, neutralScale: settings.neutralScale) }
        }
    }
    private var db: OpaquePointer?
    private let key: SymmetricKey
    private let lock = NSLock()
    private let maximumBytes: Int
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL, key: Data, maximumBytes: Int = 8 * 1024 * 1024, busyTimeoutMilliseconds: Int32 = 5000) throws {
        guard key.count == 32, maximumBytes > 0, maximumBytes <= 64 * 1024 * 1024,
              url.isFileURL, busyTimeoutMilliseconds >= 0 else { throw Failure.invalidInput }
        self.key = SymmetricKey(data: key); self.maximumBytes = maximumBytes
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW
        // Resolve parent aliases (macOS /var -> /private/var), while refusing a
        // symlink at the database itself through SQLITE_OPEN_NOFOLLOW.
        guard let resolved = realpath(url.deletingLastPathComponent().path, nil) else { throw Failure.invalidInput }
        let parent = String(cString: resolved); free(resolved)
        let path = URL(fileURLWithPath: parent).appendingPathComponent(url.lastPathComponent).path
        let result = sqlite3_open_v2(path, &db, flags, nil)
        guard result == SQLITE_OK else { if let db { sqlite3_close(db) }; db = nil; throw Failure.database(result) }
        do {
            try check(sqlite3_busy_timeout(db, busyTimeoutMilliseconds))
            guard chmod(path, 0o600) == 0 else { throw Failure.invalidInput }
            let version = try scalar("PRAGMA user_version")
            guard version == 0 || version == 1 else { throw Failure.incompatibleSchema }
            let mode = try prepare("PRAGMA journal_mode=WAL")
            defer { sqlite3_finalize(mode) }
            guard sqlite3_step(mode) == SQLITE_ROW,
                  let text = sqlite3_column_text(mode,0), String(cString: text) == "wal" else { throw Failure.incompatibleSchema }
            // Finish pragma before subsequent schema writes.
            guard sqlite3_step(mode) == SQLITE_DONE else { throw Failure.database(sqlite3_errcode(db)) }
            try execute("PRAGMA synchronous=FULL")
            try execute("BEGIN IMMEDIATE")
            do {
                try execute("CREATE TABLE IF NOT EXISTS profiles (id TEXT PRIMARY KEY NOT NULL, revision INTEGER NOT NULL CHECK(revision>0), payload BLOB NOT NULL)")
                if version == 0 { try execute("PRAGMA user_version=1") }
                try execute("COMMIT")
            } catch { try? execute("ROLLBACK"); throw error }
        } catch { sqlite3_close(db); db = nil; throw error }
    }
    deinit { if let db { sqlite3_close(db) } }
    func close() throws {
        lock.lock(); defer { lock.unlock() }
        guard let db else { return }
        let status = sqlite3_close(db)
        guard status == SQLITE_OK else { throw Failure.database(status) }
        self.db = nil
    }
    /// expectedRevision=0 creates; a nonzero revision provides compare-and-swap.
    /// Fault hooks are test-only and must not reenter this instance.
    @discardableResult
    func save(id: String, metadata: [String: Codec.Value], classifier: Codec.Classifier,
              settings: Settings, expectedRevision: Int64,
              fault: ((WriteStage) throws -> Void)? = nil) throws -> Int64 {
        lock.lock(); defer { lock.unlock() }
        try validateID(id)
        guard metadata["uuid"] == .string(id), expectedRevision >= 0,
              expectedRevision < Int64.max else { throw Failure.invalidInput }
        _ = try ReferenceTrainingMetadata.decode(metadata)
        _ = try ReferenceRuntimeProfile.runtime(classifier,classPriors: settings.classPriors,neutralScale: settings.neutralScale)
        let object: [String: Codec.Value] = ["schemaVersion": .number(1), "metadata": .object(metadata),
            "classifier": .object(try Codec.encodeClassifier(classifier)),
            "priors": .array(settings.classPriors.map(Codec.Value.number)), "neutralScale": .number(settings.neutralScale)]
        let bytes = try Codec.encodeJSONObject(object,maximumBytes: maximumBytes,maximumNesting: 32)
        let revision = expectedRevision + 1
        let payload = try AES.GCM.seal(bytes,using: key,authenticating: aad(id,revision)).combined!
        try execute("BEGIN IMMEDIATE")
        var committed = false
        do {
            let current = try readRow(id)?.0 ?? 0
            guard current == expectedRevision else { throw Failure.conflict }
            let statement = try prepare("INSERT INTO profiles(id,revision,payload) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET revision=excluded.revision,payload=excluded.payload")
            defer { sqlite3_finalize(statement) }
            try check(sqlite3_bind_text(statement,1,id,-1,transient))
            try check(sqlite3_bind_int64(statement,2,revision))
            try payload.withUnsafeBytes { try check(sqlite3_bind_blob(statement,3,$0.baseAddress,Int32($0.count),transient)) }
            guard sqlite3_step(statement) == SQLITE_DONE else { throw Failure.database(sqlite3_errcode(db)) }
            try fault?(.beforeCommit)
            try execute("COMMIT"); committed = true
            do { try fault?(.afterCommit) } catch { throw Failure.committedWithoutAcknowledgement(revision) }
            return revision
        } catch { if !committed { try? execute("ROLLBACK") }; throw error }
    }
    func load(id: String) throws -> Record? {
        lock.lock(); defer { lock.unlock() }
        try validateID(id)
        guard let (revision,payload) = try readRow(id) else { return nil }
        let bytes: Data
        do { bytes = try AES.GCM.open(AES.GCM.SealedBox(combined: payload),using: key,authenticating: aad(id,revision)) }
        catch { throw Failure.corrupt }
        let object = try Codec.decodeJSONObject(bytes,maximumBytes: maximumBytes,maximumNesting: 32)
        guard object["schemaVersion"] == .number(1), case let .object(metadata)? = object["metadata"],
              metadata["uuid"] == .string(id), case let .object(attributes)? = object["classifier"],
              case let .array(priors)? = object["priors"], case let .number(scale)? = object["neutralScale"] else { throw Failure.corrupt }
        _ = try ReferenceTrainingMetadata.decode(metadata)
        let decoded = try Codec.decodeClassifier(attributes,maximumElements: maximumBytes / 8)
        guard decoded.schemaAccepted, let classifier = decoded.classifier else { throw Failure.corrupt }
        let weights = try priors.map { value -> Double in guard case let .number(x) = value else { throw Failure.corrupt }; return x }
        let record = Record(metadata: metadata,classifier: classifier,settings: .init(classPriors: weights,neutralScale: scale),revision: revision)
        _ = try record.runtime
        return record
    }
    private func aad(_ id: String,_ revision: Int64) -> Data { Data("eeg-reference-profile-v1|\(id)|\(revision)".utf8) }
    private func validateID(_ id: String) throws {
        guard !id.isEmpty, id.utf8.count <= 128,
              id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else { throw Failure.invalidInput }
    }
    private func check(_ status: Int32) throws { guard status == SQLITE_OK else { throw Failure.database(status) } }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let db else { throw Failure.closed }
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(db,sql,-1,&statement,nil)
        if result != SQLITE_OK { sqlite3_finalize(statement); throw Failure.database(result) }
        guard let statement else { throw Failure.corrupt }; return statement
    }
    private func execute(_ sql: String) throws {
        guard let db else { throw Failure.closed }
        try check(sqlite3_exec(db,sql,nil,nil,nil))
    }
    private func scalar(_ sql: String) throws -> Int64 {
        let statement = try prepare(sql); defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw Failure.corrupt }
        return sqlite3_column_int64(statement,0)
    }
    private func readRow(_ id: String) throws -> (Int64,Data)? {
        let statement = try prepare("SELECT revision,payload FROM profiles WHERE id=?")
        defer { sqlite3_finalize(statement) }
        try check(sqlite3_bind_text(statement,1,id,-1,transient))
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else { throw Failure.database(result) }
        let revision = sqlite3_column_int64(statement,0), count = Int(sqlite3_column_bytes(statement,1))
        guard revision > 0, count > 0, count <= maximumBytes + 28,
              let pointer = sqlite3_column_blob(statement,1) else { throw Failure.resourceLimit }
        return (revision,Data(bytes: pointer,count: count))
    }
}
