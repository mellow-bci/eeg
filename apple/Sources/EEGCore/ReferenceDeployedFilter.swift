import Foundation

/// Body-derived RealTimeFilter order-two comparison path; not a live acquisition filter.
/// Caller supplies the two coefficient lists in their recovered argument order.
/// Histories start at the first sample, persist across blocks, and reset when channel count changes.
struct ReferenceDeployedFilter {
    enum Failure: Error { case invalidConfiguration, invalidBlock, capacityExceeded, nonfiniteResult }
    let numerator: [Double]
    let feedback: [Double]
    let maximumChannels: Int
    let maximumSamplesPerBlock: Int
    private var inputHistory: [[Double]] = []
    private var outputHistory: [[Double]] = []
    init(numerator: [Double], feedback: [Double], maximumChannels: Int,
                maximumSamplesPerBlock: Int) throws {
        guard numerator.count == 3, feedback.count == 3,
              numerator.allSatisfy(\.isFinite), feedback.allSatisfy(\.isFinite),
              maximumChannels > 0, maximumSamplesPerBlock > 0 else { throw Failure.invalidConfiguration }
        self.numerator = numerator; self.feedback = feedback
        self.maximumChannels = maximumChannels; self.maximumSamplesPerBlock = maximumSamplesPerBlock
    }
    /// Coefficients passed by CognitivDetectionManager::init to manager+0xb38.
    /// No sample-rate/cutoff interpretation is claimed from these constants alone.
    static func deployed(maximumChannels: Int, maximumSamplesPerBlock: Int) throws -> Self {
        try Self(numerator: [0.97554449992839098, -1.9510888162127069, 0.97554449992839098],
                 feedback: [1, -1.9504906552523591, 0.95168716081713],
                 maximumChannels: maximumChannels, maximumSamplesPerBlock: maximumSamplesPerBlock)
    }
    mutating func reset() { inputHistory = []; outputHistory = [] }
    /// Rows are channels; columns are samples. Empty sample blocks are explicitly unsupported:
    /// the reference initializes from input[0] even before checking the sample count.
    mutating func apply(_ rows: [[Double]]) throws -> [[Double]] {
        guard !rows.isEmpty, let count = rows.first?.count, count > 0,
              rows.allSatisfy({ $0.count == count && $0.allSatisfy(\.isFinite) }) else { throw Failure.invalidBlock }
        guard rows.count <= maximumChannels, count <= maximumSamplesPerBlock else { throw Failure.capacityExceeded }
        var previousInputs = inputHistory
        var previousOutputs = outputHistory
        if previousInputs.count != rows.count {
            previousInputs = rows.map { Array(repeating: $0[0], count: 2) }
            previousOutputs = previousInputs
        }
        var result = rows
        for channel in rows.indices {
            var xs = previousInputs[channel]
            var ys = previousOutputs[channel]
            for index in rows[channel].indices {
                let x = rows[channel][index]
                // Preserve the reference's ordered fused multiply-add/subtract operations.
                var y = 0.0.addingProduct(numerator[0], x)
                y = y.addingProduct(numerator[1], xs[1])
                y = y.addingProduct(numerator[2], xs[0])
                y = y.addingProduct(-feedback[1], ys[1])
                y = y.addingProduct(-feedback[2], ys[0])
                guard y.isFinite else { throw Failure.nonfiniteResult }
                result[channel][index] = y
                xs = [xs[1], x]; ys = [ys[1], y]
            }
            previousInputs[channel] = xs; previousOutputs[channel] = ys
        }
        inputHistory = previousInputs; outputHistory = previousOutputs
        return result
    }
}
