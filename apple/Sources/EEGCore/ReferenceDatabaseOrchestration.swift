/// Comparison contracts for the traced cache/NoSQL save path. Callbacks must
/// perform real operations; return codes never imply atomicity or fsync.
enum ReferenceDatabaseOrchestration {
    typealias Failure = ReferenceProfileIO.Failure
    enum DomainError: Error { case mismatchedIDs }
    struct WriteResult: Equatable { let attempts: Int; let code: Int }
    enum AttributeSaveResult: Equatable {
        /// The vendor ignores invokeMethod's result. Preserve it diagnostically;
        /// zero reportedCode is neither successful enqueue nor durable success.
        case queued(invocationAccepted: Bool, reportedCode: Int)
        case synchronous(fileAttempts: Int, code: Int)
    }

    /// NoSQLDatabase::saveDoc retries only0x3102, ten total calls. It sleeps5ms
    /// after every such result, including the final exhausted attempt.
    static func writeDocument<Driver>(acquireDriver: () -> Result<Driver, Failure>,
                                      write: (Driver) -> Int,
                                      sleepMilliseconds: (Int) -> Void) -> WriteResult {
        let driver: Driver
        switch acquireDriver() {
        case let .success(value): driver = value
        case let .failure(error): return .init(attempts: 0, code: error.code)
        }
        var attempts = 0
        var code: Int
        repeat {
            attempts += 1
            code = write(driver)
            if code == 0x3102 { sleepMilliseconds(5) }
        } while code == 0x3102 && attempts < 10
        return .init(attempts: attempts, code: code)
    }

    /// Both wrapper saveDoc and saveTrainingProfile return the original write
    /// result. A configured updater is notified only on zero plus the third flag.
    static func saveDocument(notifyChanges: Bool, updaterAvailable: Bool,
                             save: () -> Int, addChanges: () -> Void) -> Int {
        let code = save()
        if code == 0 && notifyChanges && updaterAvailable { addChanges() }
        return code
    }

    /// Profile cache publication precedes metadata then attribute saving. There
    /// is no rollback in the inspected body. Mismatched IDs are an exceptional
    /// domain; reject them explicitly before callbacks instead of guessing Qt.
    static func updateProfileCache(profileID: String, attributesID: String,
                                   publishCache: () -> Void,
                                   saveMetadata: () -> Int, saveAttributes: () -> Int) throws -> Int {
        guard profileID == attributesID else { throw DomainError.mismatchedIDs }
        publishCache()
        let code = saveMetadata()
        return code == 0 ? saveAttributes() : code
    }

    /// Normal first-flag=false path only. The queued path deliberately returns
    /// reported zero even when invocation fails, exposing that distinction here.
    /// The synchronous path calls the metadata helper directly after file success.
    static func saveAttributes(queued: Bool, invokeSave: () -> Bool,
                               writeFile: () -> Int, saveMetadataAfterFile: () -> Int) -> AttributeSaveResult {
        if queued { return .queued(invocationAccepted: invokeSave(), reportedCode: 0) }
        let write = ReferenceProfileIO.writeWorker(save: writeFile, completed: { _ in })
        let code = write.code == 0 ? saveMetadataAfterFile() : write.code
        return .synchronous(fileAttempts: write.attempts, code: code)
    }

    /// TrainingProfileAttributesInternal::toJsonObject writes only the UUID;
    /// classifier/training data live in the separate attribute file.
    static func attributeMetadata(profileID: String) -> [String: ReferenceProfileCodec.Value] {
        ["uuid": .string(profileID)]
    }
}
