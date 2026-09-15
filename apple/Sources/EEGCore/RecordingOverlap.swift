import Foundation

/// Exact canonical sample-block reuse within one dataset, independent of file names
/// and receive timestamps. Rolling hashes only locate candidates; bytes prove a match.
struct EEGRecordingOverlapIndex {
    static let blockSamples = 256
    private static let sampleBytes = 30 // UInt16 counter plus 14 UInt16 ADC channels
    private static let blockBytes = blockSamples * sampleBytes
    private static let base: UInt64 = 257
    private static let outgoingWeight: UInt64 = {
        var value: UInt64 = 1
        for _ in 1..<blockBytes { value = value &* base }
        return value
    }()
    private var blocks = [UInt64: Set<Data>]()

    struct Scanner {
        fileprivate var ring = [UInt8](repeating: 0, count: EEGRecordingOverlapIndex.blockBytes)
        fileprivate var position = 0, filled = 0, samples = 0
        fileprivate var hash: UInt64 = 0
        fileprivate var pending = [UInt64: Set<Data>]()
        private(set) var reusedBlock = false
        fileprivate func orderedBytes() -> Data {
            Data(ring[position...] + ring[..<position])
        }
        fileprivate mutating func markReuse() { reusedBlock = true }
    }

    func append(_ sample: EEGSample, to scanner: inout Scanner) throws {
        guard (0...65535).contains(sample.counter) else { throw EEGRecordingError.invalidData }
        var words = [UInt16(sample.counter)]
        for channel in EEGMentalFeatures.channelOrder {
            guard let value = sample.electrodesADC[channel], value.isFinite,
                  value >= 0, value <= 65535, value.rounded() == value else { throw EEGRecordingError.invalidData }
            words.append(UInt16(value))
        }
        for word in words {
            for byte in [UInt8(truncatingIfNeeded: word), UInt8(truncatingIfNeeded: word >> 8)] {
                if scanner.filled == Self.blockBytes {
                    scanner.hash = scanner.hash &- (UInt64(scanner.ring[scanner.position]) &* Self.outgoingWeight)
                } else { scanner.filled += 1 }
                scanner.hash = scanner.hash &* Self.base &+ UInt64(byte)
                scanner.ring[scanner.position] = byte
                scanner.position = (scanner.position + 1) % Self.blockBytes
            }
        }
        scanner.samples += 1
        guard scanner.filled == Self.blockBytes else { return }
        // Scan every sample offset against sparse blocks of earlier sessions.
        let candidates = blocks[scanner.hash]
        let retain = scanner.samples % Self.blockSamples == 0
        if candidates != nil || retain {
            let bytes = scanner.orderedBytes()
            if candidates?.contains(bytes) == true { scanner.markReuse() }
            if retain { scanner.pending[scanner.hash, default: []].insert(bytes) }
        }
    }

    mutating func commit(_ scanner: Scanner) {
        for (hash, values) in scanner.pending { blocks[hash, default: []].formUnion(values) }
    }
}
