import Foundation
import CryptoKit
import CommonCrypto

/// Observed EPOC X wire contract. Unknown revisions fail closed.
public enum EPOCProtocol {
    public static let service = "81072f40-9f3d-11e3-a9dc-0002a5d5c51b"
    public static let dataCharacteristic = "81072f41-9f3d-11e3-a9dc-0002a5d5c51b"
    public static let serialCharacteristic = "00002a25-0000-1000-8000-00805f9b34fb"
    public static let revisionCharacteristic = "00002a28-0000-1000-8000-00805f9b34fb"
    public static let configurationCharacteristic = "81072f44-9f3d-11e3-a9dc-0002a5d5c51b"
    public static let electrodeWords: [(name: String, index: Int)] = [
        ("AF3", 2), ("F7", 3), ("F3", 0), ("FC5", 1), ("T7", 4),
        ("P7", 5), ("O1", 6), ("O2", 8), ("P8", 9), ("T8", 10),
        ("FC6", 13), ("F4", 14), ("F8", 11), ("AF4", 12)
    ]
}

public enum EEGDecoderError: Error, LocalizedError, Equatable {
    case unsupportedMetadata
    case unsupportedLength(Int)
    case invalidRecordType
    case invalidCounters
    case invalidAuxiliaryType
    case invalidTimestamp
    case cryptographicFailure(Int32)

    public var errorDescription: String? {
        switch self {
        case .unsupportedMetadata: return "Only five-byte serials and software revision 0740 are supported."
        case .unsupportedLength(let count): return "Unsupported EEG notification length: \(count)."
        case .invalidRecordType: return "Unexpected EEG record type; device key or format mismatch."
        case .invalidCounters: return "Invalid within-notification sample counters."
        case .invalidAuxiliaryType: return "Unexpected auxiliary record type."
        case .invalidTimestamp: return "EEG arrival timestamp must be finite."
        case .cryptographicFailure(let status): return "AES operation failed with status \(status)."
        }
    }
}

/// ADC samples with the vendor's observed channel mapping. Voltage is uncentered.
/// This payload does not assert authenticated integrity, physiological quality or intent.
public struct EEGSample: Codable, Sendable, Equatable {
    public let index: Int
    public let counter: Int
    public let receivedAt: Double
    public let continuous: Bool
    public let adcWords: [UInt16]
    public let electrodesADC: [String: Double]
    public let electrodesMicrovolts: [String: Double]?
    public let notificationSlot: Int
    public let recordFlag: Int
    public var rawContactQuality: UInt16? { adcWords.count > 7 ? adcWords[7] : nil }
    public var integrityVerified: Bool { false }
    public var physiologyValidated: Bool { false }
}

/// Pure stateful decoder; construct a new instance for each connection epoch.
/// ECB framing checks detect many errors but are not cryptographic authentication.
public struct EEGDecoder: Sendable {
    private let key: Data
    private let xorByte: UInt8
    public let voltageDivisor: Double?
    public private(set) var sampleCount = 0
    public private(set) var discontinuities = 0
    private var previousCounter: UInt8?

    public init(serial: Data, revision: Data, configuration: Data? = nil) throws {
        let derived = try Self.deriveKey(serial: serial, revision: revision)
        key = derived.key
        xorByte = derived.xorByte
        voltageDivisor = configuration == Data([0x01, 0x80, 0x00, 0x10, 0x20, 0x10]) ? 7.8 : nil
    }

    static func deriveKey(serial: Data, revision: Data) throws -> (key: Data, xorByte: UInt8) {
        guard serial.count == 5, revision == Data([0x07, 0x40]) else {
            throw EEGDecoderError.unsupportedMetadata
        }
        // Protocol constants recovered from the local software trace, not account credentials.
        let packed: [UInt8] = [
            0x55, 0xdb, 0x70, 0x62, 0xed, 0xcd, 0x83, 0xc1, 0x55, 0x21,
            0x4d, 0xf3, 0x57, 0xdd, 0x91, 0x8b, 0x43, 0xef, 0x0e, 0x12,
            0xf3, 0x4c, 0x28, 0xbb, 0x26, 0xf9, 0x63, 0x0d, 0x40, 0xdd,
            0xe9, 0x02, 0xab, 0x83, 0xe4, 0x48, 0xdb, 0x89, 0x0d, 0x29,
            0x52, 0x28, 0xe4, 0x14
        ]
        let tail = Data(packed.suffix(12))
        let seed = [UInt8](try decrypt(Data(packed.prefix(32)), key: Data(SHA256.hash(data: tail))))
        let serialHex = Array(serial.prefix(4).map { String(format: "%02X", $0) }.joined().utf8)
        var material = Data(seed[1..<4])
        material.append(contentsOf: seed[5..<10])
        material.append(contentsOf: serialHex[0..<4])
        material.append(contentsOf: seed[11..<18])
        material.append(seed[19])
        material.append(contentsOf: serialHex[4..<8])
        material.append(contentsOf: "0740".utf8)
        return (Data(SHA256.hash(data: material)), packed.last!)
    }

    private static func decrypt(_ input: Data, key: Data) throws -> Data {
        var output = [UInt8](repeating: 0, count: input.count)
        var moved = 0
        let capacity = output.count
        let status = key.withUnsafeBytes { keyBytes in
            input.withUnsafeBytes { inputBytes in
                output.withUnsafeMutableBytes { outputBytes in
                    CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionECBMode), keyBytes.baseAddress, key.count,
                            nil, inputBytes.baseAddress, input.count,
                            outputBytes.baseAddress, capacity, &moved)
                }
            }
        }
        guard status == kCCSuccess, moved == input.count else {
            throw EEGDecoderError.cryptographicFailure(status)
        }
        return Data(output.prefix(moved))
    }

    public mutating func decode(packet: Data, receivedAt: Double) throws -> [EEGSample] {
        guard receivedAt.isFinite else { throw EEGDecoderError.invalidTimestamp }
        guard packet.count == 64 || packet.count == 84 else {
            throw EEGDecoderError.unsupportedLength(packet.count)
        }
        let transformed = packet.map { $0 ^ xorByte }
        let alignedCount = transformed.count / 16 * 16
        var plain = [UInt8](try Self.decrypt(Data(transformed.prefix(alignedCount)), key: key))
        plain.append(contentsOf: transformed.suffix(transformed.count-alignedCount))
        // Validate the entire packet before mutating counters or returning any sample.
        guard plain[1] & 0x7f == 0x10, plain[33] & 0x7f == 0x10 else {
            throw EEGDecoderError.invalidRecordType
        }
        guard plain[0] < 128, plain[32] < 128,
              (Int(plain[32])-Int(plain[0])+128) % 128 == 1 else {
            throw EEGDecoderError.invalidCounters
        }
        guard plain.count != 84 || plain[65] & 0x7f == 0x20 else {
            throw EEGDecoderError.invalidAuxiliaryType
        }
        var samples: [EEGSample] = []
        samples.reserveCapacity(2)
        for slot in 0..<2 {
            let offset = slot*32
            let counter = plain[offset]
            let continuous = previousCounter.map { counter == ($0+1) % 128 } ?? true
            let words: [UInt16] = (0..<15).map { word in
                let start = offset+2+word*2
                return UInt16(plain[start]) | (UInt16(plain[start+1]) << 8)
            }
            let electrodes = Dictionary(uniqueKeysWithValues: EPOCProtocol.electrodeWords.map {
                ($0.name, Double(words[$0.index]))
            })
            let microvolts = voltageDivisor.map { divisor in electrodes.mapValues { $0 / divisor } }
            samples.append(EEGSample(index: sampleCount, counter: Int(counter), receivedAt: receivedAt,
                                     continuous: continuous, adcWords: words, electrodesADC: electrodes,
                                     electrodesMicrovolts: microvolts, notificationSlot: slot,
                                     recordFlag: Int(plain[offset+1] >> 7)))
            previousCounter = counter
            sampleCount += 1
            if !continuous { discontinuities += 1 }
        }
        return samples
    }
}
