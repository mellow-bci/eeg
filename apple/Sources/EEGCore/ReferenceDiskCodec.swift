import Foundation
import zlib
import CommonCrypto

/// Comparison-only recovered gzip framing and AES-256-CBC envelope.
/// Keys/IVs belong to the caller; vendor identifier/salt derivation is deliberately absent.
/// CBC is unauthenticated and this type makes no storage durability guarantee.
struct ReferenceDiskCodec {
    enum Failure: Error { case invalidConfiguration, capacityExceeded, malformedCompressedData, invalidKeyOrIV, cryptographicFailure(Int32) }
    let maximumPlaintextBytes: Int
    let maximumEncodedBytes: Int
    init(maximumPlaintextBytes: Int, maximumEncodedBytes: Int) throws {
        guard maximumPlaintextBytes >= 0, maximumPlaintextBytes < Int(UInt32.max),
              maximumEncodedBytes >= 32, maximumEncodedBytes < Int(UInt32.max) else { throw Failure.invalidConfiguration }
        self.maximumPlaintextBytes = maximumPlaintextBytes
        self.maximumEncodedBytes = maximumEncodedBytes
    }
    func compress(_ input: Data) throws -> Data {
        guard input.count <= maximumPlaintextBytes else { throw Failure.capacityExceeded }
        var stream = z_stream()
        guard deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY,
                           ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw Failure.malformedCompressedData }
        defer { deflateEnd(&stream) }
        var raw = [UInt8](repeating: 0, count: maximumEncodedBytes - 18)
        let status = input.withUnsafeBytes { source in raw.withUnsafeMutableBytes { destination in
            stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(input.count)
            stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress
            stream.avail_out = uInt(destination.count)
            return deflate(&stream, Z_FINISH)
        } }
        guard status == Z_STREAM_END else { throw Failure.capacityExceeded }
        var result = Data([0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 0x0b])
        result.append(contentsOf: raw.prefix(Int(stream.total_out)))
        let checksum = input.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(input.count)) }
        for value in [UInt32(truncatingIfNeeded: checksum), UInt32(input.count)] {
            result.append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
        }
        return result
    }
    /// Strict bounded own policy: require completed single stream and no trailing bytes.
    /// Reference inflate accepts gzip/zlib (windowBits47); permissive partial-output behavior is not reproduced.
    func decompress(_ input: Data) throws -> Data {
        guard input.count <= maximumEncodedBytes else { throw Failure.capacityExceeded }
        guard input.count > 4 else { throw Failure.malformedCompressedData }
        var stream = z_stream()
        guard inflateInit2_(&stream, 47, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw Failure.malformedCompressedData }
        defer { inflateEnd(&stream) }
        var output = [UInt8](repeating: 0, count: maximumPlaintextBytes + 1)
        let status = input.withUnsafeBytes { source in output.withUnsafeMutableBytes { destination in
            stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(input.count)
            stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress
            stream.avail_out = uInt(destination.count)
            return inflate(&stream, Z_FINISH)
        } }
        guard stream.total_out <= maximumPlaintextBytes else { throw Failure.capacityExceeded }
        guard status == Z_STREAM_END, stream.avail_in == 0 else { throw Failure.malformedCompressedData }
        return Data(output.prefix(Int(stream.total_out)))
    }
    /// Reproducible comparison API requires an explicit16-byte IV; callers must generate fresh random IVs for real encryption.
    func encrypt(_ input: Data, key: Data, iv: Data) throws -> Data {
        guard input.count <= maximumEncodedBytes - 32 else { throw Failure.capacityExceeded }
        return iv + (try crypt(input, key: key, iv: iv, operation: CCOperation(kCCEncrypt)))
    }
    func decrypt(_ envelope: Data, key: Data) throws -> Data {
        guard envelope.count <= maximumEncodedBytes else { throw Failure.capacityExceeded }
        guard envelope.count >= 32, (envelope.count - 16) % 16 == 0 else { throw Failure.invalidKeyOrIV }
        return try crypt(Data(envelope.dropFirst(16)), key: key, iv: Data(envelope.prefix(16)), operation: CCOperation(kCCDecrypt))
    }
    private func crypt(_ input: Data, key: Data, iv: Data, operation: CCOperation) throws -> Data {
        guard key.count == 32, iv.count == 16 else { throw Failure.invalidKeyOrIV }
        var output = [UInt8](repeating: 0, count: input.count + 16)
        var written = 0
        let status = key.withUnsafeBytes { k in iv.withUnsafeBytes { v in input.withUnsafeBytes { source in output.withUnsafeMutableBytes { destination in
            CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES), operation == CCOperation(kCCDecrypt) ? 0 : CCOptions(kCCOptionPKCS7Padding), k.baseAddress, 32,
                    v.baseAddress, source.baseAddress, input.count, destination.baseAddress, destination.count, &written)
        } } } }
        guard status == kCCSuccess else { throw Failure.cryptographicFailure(status) }
        if operation == CCOperation(kCCDecrypt) {
            // Native CommonCrypto PKCS7 accepts some malformed padding. Validate the
            // unpadded CBC bytes explicitly to match EVP_CipherFinal_ex failure semantics.
            guard written > 0 else { throw Failure.cryptographicFailure(Int32(kCCDecodeError)) }
            let padding = Int(output[written - 1])
            guard (1...16).contains(padding), padding <= written,
                  output[(written - padding)..<written].allSatisfy({ Int($0) == padding }) else {
                throw Failure.cryptographicFailure(Int32(kCCDecodeError))
            }
            written -= padding
        }
        return Data(output.prefix(written))
    }
}
