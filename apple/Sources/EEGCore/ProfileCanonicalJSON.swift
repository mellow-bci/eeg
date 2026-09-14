import Foundation
import CryptoKit

/// Canonicalizes Python-generated profile JSON without rounding floating-point
/// tokens through Foundation. Whitespace/key order may vary; numeric and string
/// token spellings must match the Python serializer used to create the checksum.
/// This is an integrity check, not authentication or proof of training provenance.
enum ProfileCanonicalJSON {
    enum Failure: Error { case malformed }
    indirect enum Value {
        case scalar(String)
        case array([Value])
        case object([(String, String, Value)])
        var text: String {
            switch self {
            case .scalar(let s): return s
            case .array(let a): return "[" + a.map(\.text).joined(separator: ",") + "]"
            case .object(let o):
                return "{" + o.sorted { $0.0.utf8.lexicographicallyPrecedes($1.0.utf8) }
                    .map { $0.1 + ":" + $0.2.text }.joined(separator: ",") + "}"
            }
        }
    }
    static func digest(_ data: Data) throws -> String {
        guard data.count <= 8 * 1024 * 1024 else { throw Failure.malformed }
        // Reject invalid JSON tokens before retaining their source spelling.
        _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        var parser = Parser(bytes: Array(data))
        let root = try parser.value(depth: 0)
        parser.space()
        guard parser.position == parser.bytes.count, case .object(let fields) = root,
              fields.contains(where: { $0.0 == "profile_id" }) else { throw Failure.malformed }
        let canonical = Value.object(fields.filter { $0.0 != "profile_id" }).text
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private struct Parser {
        let bytes: [UInt8]
        var position = 0
        mutating func space() { while position < bytes.count && [9,10,13,32].contains(bytes[position]) { position += 1 } }
        mutating func take(_ byte: UInt8) throws {
            space(); guard position < bytes.count, bytes[position] == byte else { throw Failure.malformed }; position += 1
        }
        mutating func string() throws -> (String, String) {
            space(); let start = position; try take(34)
            while position < bytes.count {
                let byte = bytes[position]; position += 1
                if byte == 92 { guard position < bytes.count else { throw Failure.malformed }; position += 1 }
                else if byte == 34 {
                    let raw = Data(bytes[start..<position])
                    guard let decoded = try JSONSerialization.jsonObject(with: raw, options: [.fragmentsAllowed]) as? String,
                          let spelling = String(data: raw, encoding: .utf8) else { throw Failure.malformed }
                    return (decoded, spelling)
                }
            }
            throw Failure.malformed
        }
        mutating func value(depth: Int) throws -> Value {
            guard depth < 64 else { throw Failure.malformed }
            space(); guard position < bytes.count else { throw Failure.malformed }
            switch bytes[position] {
            case 34: return .scalar(try string().1)
            case 123:
                position += 1; space(); var fields = [(String,String,Value)](); var keys = Set<String>()
                if position < bytes.count, bytes[position] == 125 { position += 1; return .object(fields) }
                while true {
                    let (key, raw) = try string()
                    guard keys.insert(key).inserted else { throw Failure.malformed }
                    try take(58); let child = try value(depth: depth + 1); fields.append((key,raw,child)); space()
                    guard position < bytes.count else { throw Failure.malformed }
                    if bytes[position] == 125 { position += 1; return .object(fields) }
                    try take(44)
                }
            case 91:
                position += 1; space(); var values = [Value]()
                if position < bytes.count, bytes[position] == 93 { position += 1; return .array(values) }
                while true {
                    values.append(try value(depth: depth + 1)); space()
                    guard position < bytes.count else { throw Failure.malformed }
                    if bytes[position] == 93 { position += 1; return .array(values) }
                    try take(44)
                }
            default:
                let start = position
                while position < bytes.count && ![9,10,13,32,44,93,125].contains(bytes[position]) { position += 1 }
                guard position > start, let token = String(bytes: bytes[start..<position], encoding: .utf8) else { throw Failure.malformed }
                return .scalar(token)
            }
        }
    }
}
