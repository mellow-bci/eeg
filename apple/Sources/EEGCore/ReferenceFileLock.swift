/// Comparison-only FileLocker/caller lifecycle, not an operating-system lock.
/// Lock, diagnostic and data operations must be provided by the caller.
enum ReferenceFileLock {
    enum LockError: Error { case negativeTimeout }
    enum Outcome<Value> { case unavailable; case performed(Value) }

    static func lockPath(dataPath: String) -> String { dataPath + ".lock" }

    /// FileLocker calls tryLock once. Callers separately inspect isLocked rather
    /// than using that return value. Cleanup unlocks even when acquisition fails.
    /// Requiring a nonnegative timeout is our bounded policy; vendor forwards int.
    static func perform<Value>(timeoutMilliseconds: Int32,
                               tryLock: (Int32) -> Bool,
                               acquisitionFailed: () -> Void,
                               isLocked: () -> Bool,
                               unlock: () -> Void,
                               dispose: () -> Void,
                               operation: () throws -> Value) throws -> Outcome<Value> {
        guard timeoutMilliseconds >= 0 else { throw LockError.negativeTimeout }
        defer { unlock(); dispose() }
        if !tryLock(timeoutMilliseconds) { acquisitionFailed() }
        guard isLocked() else { return .unavailable }
        return .performed(try operation())
    }
}
