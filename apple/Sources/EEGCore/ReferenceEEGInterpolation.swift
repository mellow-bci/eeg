import Foundation

/// Comparison-only recovered interpolation kernels. No live acquisition routing.
/// Evidence: interpolation-continuation-20261011. Interpolated values are separate
/// from measurements. Validation/resource rejection is our policy.
enum ReferenceEEGInterpolation {
    enum Failure: Error { case invalidInput, invalidRandomDraws, nonfiniteOutput }
    static let sourceIDs = [54, 40, 72, 92, 106]
    static let synthesizedIDs = [45, 101, 64, 82, 51, 95, 43, 103, 77, 69]
    private static let coefficientBits: [[UInt64]] = [
        [0x3fc126e978d4fdf4, 0x3fd2b1c432ca57a8, 0x3fd8faacd9e83e42, 0x3f932617c1bda512, 0x3fc594af4f0d844d],
        [0x3f9a027525460aa6, 0xbfc26e978d4fdf3b, 0x3fd781d7dbf487fd, 0x3fd92d77318fc505, 0x3fd8779a6b50b0f2],
        [0x3fdc7fcb923a29c7, 0x3fb3b645a1cac083, 0x3fd947ae147ae148, 0x3f67c1bda5119ce0, 0xbf8c0ebedfa43fe6],
        [0x3f90ff972474538f, 0x3fae0ded288ce704, 0x3fcedfa43fe5c91d, 0x3fe4027525460aa6, 0x3fb346dc5d638866],
        [0x3fce631f8a0902de, 0x3fd2b851eb851eb8, 0x3fce594af4f0d845, 0x3fb9096bb98c7e28, 0x3fbeecbfb15b573f],
        [0x3f89ce075f6fd220, 0x3fa5e9e1b089a027, 0x3fbf4f0d844d013b, 0x3fe6b0f27bb2fec5, 0x3fbae147ae147ae1],
        [0x3fa5b573eab367a1, 0x3fca92a305532618, 0x3fd652bd3c361134, 0x3fdf5c28f5c28f5c, 0xbfbea4a8c154c986],
        [0xbf847ae147ae147b, 0x3fc0793dd97f62b7, 0x3fc65c91d14e3bcd, 0x3fe3bf487fcb923a, 0x3fb60aa64c2f837b],
        [0xbfa810624dd2f1aa, 0x3fac28f5c28f5c29, 0x3fd06a7ef9db22d1, 0x3fe2dc5d63886595, 0x3fbb367a0f9096bc]
    ]
    struct SpatialResult {
        let measuredChannelIDs: [Int]
        let measuredRows: [[Double]]
        let synthesizedChannelIDs: [Int]
        let synthesizedRows: [[Double]]
        var combinedChannelIDs: [Int] { measuredChannelIDs + synthesizedChannelIDs }
        var combinedRows: [[Double]] { zip(measuredRows, synthesizedRows).map { $0 + $1 } }
    }
    /// Qt global generator state is NOT reproduced. Supply its observed UInt64
    /// draws explicitly for reference comparison, or nil to disable jitter.
    /// Each row consumes ten draws in synthesizedIDs order.
    static func spatialInsight(rows: [[Double]], channelIDs: [Int],
                               randomDraws: [UInt64]?, maximumRows: Int) throws -> SpatialResult {
        guard maximumRows >= 0, rows.count <= maximumRows,
              channelIDs.count >= 5, channelIDs.count <= 70,
              Set(channelIDs).count == channelIDs.count,
              synthesizedIDs.allSatisfy({ !channelIDs.contains($0) }),
              rows.allSatisfy({ $0.count == channelIDs.count && $0.allSatisfy(\.isFinite) }),
              sourceIDs.allSatisfy(channelIDs.contains), rows.count <= Int.max / 10 else {
            throw Failure.invalidInput
        }
        if let draws = randomDraws, draws.count != rows.count * 10 { throw Failure.invalidRandomDraws }
        let indexes = sourceIDs.map { channelIDs.firstIndex(of: $0)! }
        let coefficients = coefficientBits.map { $0.map(Double.init(bitPattern:)) }
        var generated = [[Double]]()
        for (rowIndex, row) in rows.enumerated() {
            let source = indexes.map { row[$0] }
            var values = coefficients.map { coefficients -> Double in
                var value = source[0] * coefficients[0]
                for j in 1..<5 { value = value.addingProduct(source[j], coefficients[j]) }
                return value
            }
            values.append(source[2])
            if let draws = randomDraws {
                for j in values.indices { values[j] *= randomMultiplier(draw: draws[rowIndex * 10 + j]) }
            }
            guard values.allSatisfy(\.isFinite) else { throw Failure.nonfiniteOutput }
            generated.append(values)
        }
        return .init(measuredChannelIDs: channelIDs, measuredRows: rows,
                     synthesizedChannelIDs: synthesizedIDs, synthesizedRows: generated)
    }
    static func randomMultiplier(draw: UInt64) -> Double {
        let uniform = Double(draw >> 11) * Double(bitPattern: 0x3ca0000000000000)
        let scaled = uniform * Double(bitPattern: 0x3f60624dd2f1a9fc)
        let centered = scaled + Double(bitPattern: 0xbf50624dd2f1a9fc)
        return centered + 1
    }
    /// Scalar channel portion of DataInterpolation::interpolate only. Does not
    /// synthesize package timestamps, counters, CQ or packet-status metadata.
    static func gapValues(previous: [Double], current: [Double], missing: Int) throws -> [[Double]] {
        guard (0...64).contains(missing), !previous.isEmpty, previous.count <= 70,
              previous.count == current.count,
              previous.allSatisfy(\.isFinite), current.allSatisfy(\.isFinite) else { throw Failure.invalidInput }
        let delta = zip(previous, current).map { ($1 - $0) / Double(missing + 1) }
        let result = (0..<missing).map { k in
            zip(previous, delta).map { $0.addingProduct($1, Double(k + 1)) }
        }
        guard result.allSatisfy({ $0.allSatisfy(\.isFinite) }) else { throw Failure.nonfiniteOutput }
        return result
    }
    /// Recovered modulo and 1...65 distance gate. nil means vendor's bounded
    /// interpolation branch rejects the distance, not that no packet was lost.
    static func missingCount(previousCounter: Int, currentCounter: Int, maximumCounter: Int) throws -> Int? {
        guard (1...65535).contains(maximumCounter), (0...maximumCounter).contains(previousCounter),
              (0...maximumCounter).contains(currentCounter) else { throw Failure.invalidInput }
        let modulus = maximumCounter + 1
        let distance = ((currentCounter - previousCounter) % modulus + modulus) % modulus
        return (1...65).contains(distance) ? distance - 1 : nil
    }
}
