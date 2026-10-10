import XCTest
@testable import EEGCore

final class ReferenceDiskCodecTests: XCTestCase {
    private let plain = Data("EEG independent fixture".utf8)
    private let key = Data(0..<32)
    private let iv = Data(0..<16)
    private func hex(_ string: String) -> Data {
        let chars = Array(string)
        return Data(stride(from: 0, to: chars.count, by: 2).map { UInt8(String(chars[$0...$0+1]), radix: 16)! })
    }
    func testOwnKeyCBCMatchesIndependentOpenSSLFixture() throws {
        let codec = try ReferenceDiskCodec(maximumPlaintextBytes: 100, maximumEncodedBytes: 200)
        let expected = hex("000102030405060708090a0b0c0d0e0fdccceaead5ab1b9a3803f2000861e8b0cb01df0fdc63f9f126830a87891226ac")
        XCTAssertEqual(try codec.encrypt(plain, key: key, iv: iv), expected)
        XCTAssertEqual(try codec.decrypt(expected, key: key), plain)
    }
    func testGzipMatchesIndependentZlibFixtureAndRoundTrips() throws {
        let codec = try ReferenceDiskCodec(maximumPlaintextBytes: 100, maximumEncodedBytes: 200)
        let expected = hex("1f8b080000000000000b73757557c8cc4b492d48051279250a69991525a545a900291fda1117000000")
        XCTAssertEqual(try codec.compress(plain), expected)
        XCTAssertEqual(try codec.decompress(expected), plain)
        XCTAssertEqual(try codec.decompress(codec.compress(Data())), Data())
    }
    func testCorruptTruncatedAndTrailingCompressedInputsFail() throws {
        let codec = try ReferenceDiskCodec(maximumPlaintextBytes: 100, maximumEncodedBytes: 200)
        let compressed = try codec.compress(plain)
        var corrupt = compressed; corrupt[corrupt.count - 8] ^= 1
        XCTAssertThrowsError(try codec.decompress(corrupt))
        XCTAssertThrowsError(try codec.decompress(compressed.dropLast()))
        XCTAssertThrowsError(try codec.decompress(compressed + Data([0])))
    }
    func testCapsAndMalformedCryptoFailExplicitly() throws {
        let codec = try ReferenceDiskCodec(maximumPlaintextBytes: 2, maximumEncodedBytes: 64)
        XCTAssertThrowsError(try codec.compress(plain))
        let generous = try ReferenceDiskCodec(maximumPlaintextBytes: 100, maximumEncodedBytes: 200)
        XCTAssertThrowsError(try codec.decompress(generous.compress(plain)))
        XCTAssertThrowsError(try codec.encrypt(Data(repeating: 0, count: 33), key: key, iv: iv))
        XCTAssertThrowsError(try generous.encrypt(plain, key: Data(), iv: iv))
        XCTAssertThrowsError(try generous.decrypt(Data([1,2,3]), key: key))
    }
    func testCompressionEncryptionFullOwnValuesRoundTripAndBadPadding() throws {
        let codec = try ReferenceDiskCodec(maximumPlaintextBytes: 100, maximumEncodedBytes: 256)
        let encrypted = try codec.encrypt(codec.compress(plain), key: key, iv: iv)
        XCTAssertEqual(try codec.decompress(codec.decrypt(encrypted, key: key)), plain)
        // Independently encrypted all-zero block has invalid PKCS7 padding.
        XCTAssertThrowsError(try codec.decrypt(hex("000102030405060708090a0b0c0d0e0f5a6e045708fb7196f02e553d02c3a692"), key: key))
        XCTAssertThrowsError(try codec.decrypt(hex("000102030405060708090a0b0c0d0e0f20620ea411f3566d9d42f3aac139e5c6"), key: key)) // inconsistent01,02 padding
        XCTAssertThrowsError(try codec.decrypt(hex("000102030405060708090a0b0c0d0e0f84719c1aa6ca8819ad2f9b8fb1d366d1"), key: key)) // padding17 exceeds block
        XCTAssertThrowsError(try codec.decrypt(encrypted.dropLast(), key: key))
    }
}
