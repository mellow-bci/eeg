import Foundation

/// Pure scalar reproduction of captured TimeUtils conversion. Host clock reads
/// remain explicit inputs; units must be known, not inferred from a timestamp.
struct ReferenceEpochSteadyClock {
    enum Failure: Error { case invalidInput }
    let anchoredEpochSeconds: Double
    let anchoredSteadySeconds: Double

    init(systemMicroseconds: Int64, steadyNanoseconds: Int64) throws {
        anchoredEpochSeconds = try Self.quantizedSeconds(microseconds: systemMicroseconds)
        anchoredSteadySeconds = try Self.quantizedSeconds(microseconds: steadyNanoseconds / 1000)
    }

    /// The captured binary divides then multiplies before truncation, so simply
    /// returning Double(microseconds)/1e6 can differ by one microsecond.
    static func quantizedSeconds(microseconds: Int64) throws -> Double {
        let divided = Double(microseconds) / 1_000_000
        let multiplied = divided * 1_000_000
        guard multiplied.isFinite, multiplied >= Double(Int64.min),
              multiplied < Double(Int64.max) else { throw Failure.invalidInput }
        return Double(Int64(multiplied.rounded(.towardZero))) / 1_000_000
    }

    func observation(suppliedTime: Double, currentSteadyNanoseconds: Int64) throws -> Double {
        guard suppliedTime.isFinite else { throw Failure.invalidInput }
        if suppliedTime > 0 { return suppliedTime }
        let steady = try Self.quantizedSeconds(microseconds: currentSteadyNanoseconds / 1000)
        // Preserve add-then-subtract order shown by fadd/fsub.
        let result = (anchoredEpochSeconds + steady) - anchoredSteadySeconds
        guard result.isFinite, result > 0 else { throw Failure.invalidInput }
        return result
    }
}
