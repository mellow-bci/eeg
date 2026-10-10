/// Comparison-only proven profile IO control flow. All storage is supplied by
/// explicit callbacks; this type provides no disk codec or pretend persistence.
enum ReferenceProfileIO {
    struct Failure: Error, Equatable { let code: Int }
    struct WriteCompletion: Equatable { let attempts: Int; let code: Int }

    /// Cache hit avoids database work. A miss checks metadata, loads attributes,
    /// and publishes to the cache only when both operations succeed.
    static func loadAttributes<Value>(cached: () -> Value?,
                                     checkMetadata: () -> Int,
                                     readAttributes: () -> Result<Value, Failure>,
                                     cacheLoaded: (Value) -> Void) -> Result<Value, Failure> {
        if let value = cached() { return .success(value) }
        let code = checkMetadata()
        guard code == 0 else { return .failure(.init(code: code)) }
        let loaded = readAttributes()
        if case let .success(value) = loaded { cacheLoaded(value) }
        return loaded
    }

    /// Actual worker makes at most six calls, retrying only numeric 0x3303.
    /// Callback success is not an assertion of atomicity or fsync durability.
    static func writeWorker(save: () -> Int, completed: (Int) -> Void) -> WriteCompletion {
        var attempts = 0
        var code = 0
        repeat {
            attempts += 1
            code = save()
        } while code == 0x3303 && attempts < 6
        completed(code)
        return .init(attempts: attempts, code: code)
    }

    /// onSaveTrainingAttributesDone skips its downstream helper on write error;
    /// on zero it propagates the downstream helper's result to the signal.
    /// The helper's database mutation is intentionally outside this contract.
    static func propagateCompletion(writeCode: Int, followup: () -> Int,
                                    emit: (Int) -> Void) -> Int {
        let code = writeCode == 0 ? followup() : writeCode
        emit(code)
        return code
    }
}
