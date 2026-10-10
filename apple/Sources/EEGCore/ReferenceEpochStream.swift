import Foundation

/// Comparison-only MatrixStream arithmetic. Rows are channels, columns samples.
/// This does not replace live capture or invent headset timing/profile defaults.
struct ReferenceEpochStream {
    enum InputError: Error, Equatable {
        case invalidConfiguration, invalidMatrix, channelMismatch, capacityExceeded
    }
    let windowSamples: Int
    let stepSamples: Int
    let maximumBufferedSamples: Int
    private(set) var cursor = 0
    private(set) var buffer: [[Double]] = []
    var bufferedSamples: Int { buffer.first?.count ?? 0 }

    init(sampleRate: Int, windowSeconds: Double, stepSeconds: Double,
         maximumBufferedSamples: Int) throws {
        guard sampleRate > 0, sampleRate <= Int(Int32.max),
              windowSeconds.isFinite, windowSeconds > 0,
              stepSeconds.isFinite, stepSeconds > 0,
              maximumBufferedSamples > 0, maximumBufferedSamples <= Int(Int32.max) else {
            throw InputError.invalidConfiguration
        }
        let window = Double(sampleRate) * windowSeconds
        let step = Double(sampleRate) * stepSeconds
        guard window.isFinite, step.isFinite, window >= 1, step >= 1,
              window <= Double(maximumBufferedSamples), step <= window else {
            throw InputError.invalidConfiguration
        }
        // FCVTZU: positive finite products truncate; no nearest-sample rounding.
        windowSamples = Int(window.rounded(.towardZero))
        stepSamples = Int(step.rounded(.towardZero))
        self.maximumBufferedSamples = maximumBufferedSamples
    }

    mutating func append(_ matrix: [[Double]]) throws {
        guard !matrix.isEmpty else { return } // Empty input is ignored by vendor.
        guard matrix.count <= 70, let columns = matrix.first?.count,
              matrix.allSatisfy({ $0.count == columns && $0.allSatisfy(\.isFinite) }) else {
            throw InputError.invalidMatrix
        }
        guard columns > 0 else { return }
        guard buffer.isEmpty || buffer.count == matrix.count else { throw InputError.channelMismatch }
        guard columns <= maximumBufferedSamples - bufferedSamples else { throw InputError.capacityExceeded }
        if buffer.isEmpty { buffer = matrix }
        else { for channel in buffer.indices { buffer[channel].append(contentsOf: matrix[channel]) } }
    }

    /// One invocation yields at most one epoch. Missing samples leave cursor
    /// and buffer unchanged; backlog is never drained implicitly.
    mutating func next() -> [[Double]]? {
        guard !buffer.isEmpty, cursor <= bufferedSamples,
              windowSamples <= bufferedSamples - cursor else { return nil }
        let end = cursor + windowSamples
        let result = buffer.map { Array($0[cursor..<end]) }
        cursor += stepSamples
        return result
    }

    mutating func nextWithRemoval() -> [[Double]]? {
        guard let epoch = next() else { return nil }
        // 13f03c..13f068 keeps [advanced cursor, last column], all rows.
        if cursor == bufferedSamples { buffer = [] }
        else { buffer = buffer.map { Array($0.dropFirst(cursor)) } }
        cursor = 0
        return epoch
    }

    mutating func reset() {
        buffer = []
        cursor = 0
    }
}
