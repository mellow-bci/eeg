import Foundation
import XCTest
@testable import EEGCore

final class DecoderTests: XCTestCase {
    private var archive: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("archive/current-state")
    }

    private func data(_ hex: String) throws -> Data {
        guard hex.count % 2 == 0 else { throw TestError.badFixture }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { throw TestError.badFixture }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }
    private enum TestError: Error { case badFixture }

    private func fixture(_ filename: String) throws -> Data {
        let path = archive.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("Private raw capture fixture missing; run git lfs pull: \(filename)")
        }
        let bytes = try Data(contentsOf: path)
        XCTAssertFalse(bytes.starts(with: Data("version https://git-lfs.github.com/spec".utf8)),
                       "Run git lfs pull before parity tests")
        return bytes
    }

    private func rows(_ filename: String) throws -> [[String: Any]] {
        let contents = try String(decoding: fixture(filename), as: UTF8.self)
        return try contents.split(separator: "\n").map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
    }

    private func metadata(_ info: [String: Any], _ key: String) throws -> Data {
        if let hex = info[key] as? String { return try data(hex) }
        let dictionary = try XCTUnwrap(info[key] as? [String: Any])
        return try data(XCTUnwrap(dictionary["hex"] as? String))
    }

    private func decoder(_ info: [String: Any]) throws -> EEGDecoder {
        try EEGDecoder(serial: metadata(info, EPOCProtocol.serialCharacteristic),
                       revision: metadata(info, EPOCProtocol.revisionCharacteristic),
                       configuration: info[EPOCProtocol.configurationCharacteristic] == nil ? nil :
                        metadata(info, EPOCProtocol.configurationCharacteristic))
    }

    func testKeyMatchesIndependentPythonKnownVector() throws {
        let derived = try EEGDecoder.deriveKey(serial: data("e50213ee2b"), revision: data("0740"))
        XCTAssertEqual(derived.key, try data("a08beccd77f47ae7d261a33d4fb74cdbb07a54c4376af9c87a5179b258274848"))
        XCTAssertEqual(derived.xorByte, 0x14)
    }

    func testEntireOriginalCaptureMatchesArchivedPythonADC() throws {
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("ble-capture.json")) as? [String: Any])
        let info = try XCTUnwrap(original["info"] as? [String: Any])
        let packets = try XCTUnwrap(original["packets"] as? [[String: Any]])
        var decoder = try self.decoder(info)
        var actual: [EEGSample] = []
        var auxiliaryPackets = 0
        for packet in packets where (packet["uuid"] as? String)?.lowercased() == EPOCProtocol.dataCharacteristic {
            let payload = try data(XCTUnwrap(packet["hex"] as? String))
            if payload.count == 84 { auxiliaryPackets += 1 }
            actual += try decoder.decode(packet: payload, receivedAt: XCTUnwrap(packet["t"] as? Double))
        }
        let expected = try rows("decoded-replay.jsonl").filter { $0["kind"] as? String == "eeg_adc" }
        XCTAssertEqual(actual.count, 1588)
        XCTAssertEqual(actual.count, expected.count)
        XCTAssertEqual(auxiliaryPackets, 396)
        XCTAssertEqual(decoder.discontinuities, 0)
        for (sample, row) in zip(actual, expected) {
            XCTAssertEqual(sample.index, row["index"] as? Int)
            XCTAssertEqual(sample.counter, row["counter"] as? Int)
            XCTAssertEqual(sample.adcWords.map(Int.init), row["adc_words"] as? [Int])
            XCTAssertEqual(sample.receivedAt, row["received_at"] as? Double)
            XCTAssertEqual(sample.continuous, row["continuous"] as? Bool)
            XCTAssertNil(sample.electrodesMicrovolts)
        }
    }

    func testConfiguredCaptureParityIncludingRejectedStartupAndScaling() throws {
        let original = try rows("epoc-paired-20260915-02.jsonl")
        let info = try XCTUnwrap(original.first { $0["kind"] as? String == "stream_start" }?["info"] as? [String: Any])
        var decoder = try self.decoder(info)
        var actual: [EEGSample] = []
        var errors = 0
        for packet in original where packet["kind"] as? String == "ble_notification" {
            do {
                actual += try decoder.decode(packet: data(XCTUnwrap(packet["hex"] as? String)),
                                             receivedAt: XCTUnwrap(packet["t"] as? Double))
            } catch { errors += 1 }
        }
        let expected = original.filter { $0["kind"] as? String == "eeg_adc" }
        XCTAssertEqual(actual.count, 3858)
        XCTAssertEqual(actual.count, expected.count)
        XCTAssertEqual(errors, original.filter { $0["kind"] as? String == "decode_error" }.count)
        XCTAssertEqual(decoder.discontinuities, 2)
        for (sample, row) in zip(actual, expected) {
            XCTAssertEqual(sample.index, row["index"] as? Int)
            XCTAssertEqual(sample.counter, row["counter"] as? Int)
            XCTAssertEqual(sample.adcWords.map(Int.init), row["adc_words"] as? [Int])
            XCTAssertEqual(sample.continuous, row["continuous"] as? Bool)
            XCTAssertEqual(sample.electrodesADC, row["electrodes_adc"] as? [String: Double])
            let volts = try XCTUnwrap(row["electrodes_microvolts"] as? [String: Double])
            for (name, expectedValue) in volts {
                XCTAssertEqual(try XCTUnwrap(sample.electrodesMicrovolts?[name]), expectedValue, accuracy: 1e-10)
            }
        }
    }

    func testLatestCortexRetestMatchesAllArchivedADC() throws {
        let original = try rows("epoc-cortex-retest-20260915-01.jsonl")
        let info = try XCTUnwrap(original.first { $0["kind"] as? String == "stream_start" }?["info"] as? [String: Any])
        var decoder = try self.decoder(info)
        var actual: [EEGSample] = []
        var errors = 0
        for packet in original where packet["kind"] as? String == "ble_notification" {
            do {
                actual += try decoder.decode(packet: data(XCTUnwrap(packet["hex"] as? String)),
                                             receivedAt: XCTUnwrap(packet["t"] as? Double))
            } catch { errors += 1 }
        }
        let expected = original.filter { $0["kind"] as? String == "eeg_adc" }
        XCTAssertEqual(actual.count, 15374)
        XCTAssertEqual(actual.count, expected.count)
        XCTAssertEqual(errors, 2)
        XCTAssertEqual(decoder.discontinuities, 2)
        for (sample, row) in zip(actual, expected) {
            XCTAssertEqual(sample.adcWords.map(Int.init), row["adc_words"] as? [Int])
            XCTAssertEqual(sample.counter, row["counter"] as? Int)
            XCTAssertEqual(sample.continuous, row["continuous"] as? Bool)
            XCTAssertEqual(sample.electrodesADC, row["electrodes_adc"] as? [String: Double])
        }
    }

    func testUnsupportedMetadataAndConfigurationFailClosed() throws {
        XCTAssertThrowsError(try EEGDecoder(serial: data("00"), revision: data("0740")))
        XCTAssertThrowsError(try EEGDecoder(serial: data("e50213ee2b"), revision: data("0730")))
        let decoder = try EEGDecoder(serial: data("e50213ee2b"), revision: data("0740"), configuration: data("00"))
        XCTAssertNil(decoder.voltageDivisor)
    }

    func testMalformedDecodedArrayCannotTrapContactAccessor() throws {
        let json = Data(#"{"index":0,"counter":0,"receivedAt":0,"continuous":true,"adcWords":[1,2],"electrodesADC":{},"notificationSlot":0,"recordFlag":0}"#.utf8)
        let sample = try JSONDecoder().decode(EEGSample.self, from: json)
        XCTAssertNil(sample.rawContactQuality)
    }

    func testRejectedPacketsDoNotAdvanceDecoderState() throws {
        var decoder = try EEGDecoder(serial: data("e50213ee2b"), revision: data("0740"))
        XCTAssertThrowsError(try decoder.decode(packet: Data(repeating: 0, count: 63), receivedAt: 0))
        XCTAssertThrowsError(try decoder.decode(packet: Data(repeating: 0, count: 64), receivedAt: 0))
        XCTAssertThrowsError(try decoder.decode(packet: Data(repeating: 0, count: 64), receivedAt: .nan))
        XCTAssertEqual(decoder.sampleCount, 0)
        XCTAssertEqual(decoder.discontinuities, 0)
    }
}
