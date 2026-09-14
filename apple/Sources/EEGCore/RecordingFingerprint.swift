import Foundation
import CryptoKit

/// Matches processing.workflow.recording_fingerprint: counter plus canonical
/// channel-order ADC floats per line. Filenames, metadata and timestamps do not
/// change this identity. It detects complete replay, not arbitrary shared excerpts.
struct EEGRecordingFingerprint {
    private var digest = SHA256()
    private var count = 0
    mutating func append(_ sample: EEGSample) throws {
        var values = [String]()
        for channel in EEGMentalFeatures.channelOrder {
            guard let value = sample.electrodesADC[channel], value.isFinite,
                  value >= 0, value <= 65535, value.rounded() == value else { throw EEGRecordingError.invalidData }
            // ADC range is integral and bounded. Python canonical floats always
            // use decimal integer spelling followed by .0 in this range.
            values.append("\(Int(value)).0")
        }
        digest.update(data: Data("[\(sample.counter),[\(values.joined(separator: ","))]]\n".utf8))
        count += 1
    }
    func finalize() throws -> String {
        guard count > 0 else { throw EEGRecordingError.invalidData }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
