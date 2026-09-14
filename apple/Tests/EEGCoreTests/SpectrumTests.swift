import Foundation
import XCTest
@testable import EEGCore

final class SpectrumTests: XCTestCase {
    private struct Expected: Decodable {
        let frequenciesHz: [Double]; let density: [Double]
        let rms: Double; let peakToPeak: Double; let logPowers: [Double]
    }
    private struct Fixture: Decodable {
        let channel: String; let samples: [EEGSample]; let expected: Expected
    }
    private func fixture(_ name: String) throws -> Fixture {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/spectrum/\(name).json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: path))
    }
    func testFullPSDBandsAndArtifactIndicatorsMatchPythonGoldens() throws {
        for name in ["real", "sine10"] {
            let f = try fixture(name)
            let result = try EEGSpectrum.analyze(samples: f.samples, channel: f.channel)
            XCTAssertEqual(result.frequenciesHz, f.expected.frequenciesHz)
            XCTAssertEqual(result.densityMicrovoltsSquaredPerHz.count, 129)
            for (actual, expected) in zip(result.densityMicrovoltsSquaredPerHz, f.expected.density) {
                XCTAssertEqual(actual, expected, accuracy: max(1e-9, abs(expected) * 1e-8), "\(name) PSD")
            }
            for (actual, expected) in zip(result.bands.map(\.log10Power), f.expected.logPowers) {
                XCTAssertEqual(actual, expected, accuracy: 1e-7, "\(name) integrated logpower")
            }
            XCTAssertEqual(result.detrendedRMSMicrovolts, f.expected.rms, accuracy: 1e-8)
            XCTAssertEqual(result.peakToPeakMicrovolts, f.expected.peakToPeak, accuracy: 1e-8)
        }
    }
    func testRejectsWrongWindowRateChannelGapsCalibrationAndNonfinite() throws {
        let f = try fixture("sine10")
        XCTAssertThrowsError(try EEGSpectrum.analyze(samples: Array(f.samples.prefix(255)), channel: f.channel))
        XCTAssertThrowsError(try EEGSpectrum.analyze(samples: f.samples, channel: f.channel, sampleRate: 256))
        XCTAssertThrowsError(try EEGSpectrum.analyze(samples: f.samples, channel: "not-a-channel"))
        for mode in ["index", "counter", "time", "voltage", "missing", "continuous"] {
            var samples = f.samples; let s = samples[20]
            var volts = s.electrodesMicrovolts!
            if mode == "voltage" { volts[f.channel] = .nan }
            samples[20] = EEGSample(index: mode == "index" ? 22 : s.index,
                counter: mode == "counter" ? 99 : s.counter,
                receivedAt: mode == "time" ? 100 : s.receivedAt,
                continuous: mode != "continuous", adcWords: s.adcWords,
                electrodesADC: s.electrodesADC, electrodesMicrovolts: mode == "missing" ? nil : volts,
                notificationSlot: s.notificationSlot, recordFlag: s.recordFlag)
            XCTAssertThrowsError(try EEGSpectrum.analyze(samples: samples, channel: f.channel), mode)
        }
    }
    func testFlatSignalIsFlaggedWithoutPsychologicalInterpretation() throws {
        let f = try fixture("sine10")
        let flat = f.samples.map { s in
            EEGSample(index: s.index, counter: s.counter, receivedAt: s.receivedAt, continuous: true,
                      adcWords: [UInt16](repeating: 31200, count: 15),
                      electrodesADC: s.electrodesADC.mapValues { _ in 31200 },
                      electrodesMicrovolts: s.electrodesADC.mapValues { _ in 4000 }, notificationSlot: s.notificationSlot, recordFlag: 0)
        }
        let result = try EEGSpectrum.analyze(samples: flat, channel: f.channel)
        XCTAssertFalse(result.usable)
        XCTAssertEqual(result.artifactFlags, ["flat_channel"])
        XCTAssertTrue(result.bands.allSatisfy { $0.log10Power == -12 })
    }
    func testWarmAnalysisBenchmark() throws {
        let f = try fixture("real")
        _ = try EEGSpectrum.analyze(samples: f.samples, channel: f.channel)
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<100 { _ = try EEGSpectrum.analyze(samples: f.samples, channel: f.channel) }
        let milliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000 / 100
        print("Spectrum benchmark: \(milliseconds) ms/window, warm single channel, current test build; not end-to-end latency")
    }
}
