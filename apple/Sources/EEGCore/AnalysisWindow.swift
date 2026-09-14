import Foundation

public struct EEGAnalysisWindow: Sendable {
    public let samples: [EEGSample]
    public let ordinal: Int
    public let segment: Int?
    public let reasons: [String]
    public var valid: Bool { reasons.isEmpty }
}

/// Native event-aware counterpart of the canonical nonoverlapping window gate.
/// Recording structure/word validation is supplied by EEGRecordingStore.
struct EEGAnalysisWindowAssembler {
    private var configuration: String?
    private var stable = false
    private var segment = 0
    private var ordinal = 0
    private var buffer = [EEGSample]()
    private var segments = Set<Int>()
    private var reasons = Set<String>()
    private var previous: EEGSample?
    private var previousSegment: Int?

    mutating func event(_ data: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw EEGRecordingError.invalidData }
        switch object["kind"] as? String {
        case "device_metadata":
            var metadata = object
            if let text = object["metadata_json"] as? String {
                guard let decoded = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { throw EEGRecordingError.invalidData }
                metadata = decoded
            }
            configuration = metadata.first { $0.key.lowercased() == "81072f44-9f3d-11e3-a9dc-0002a5d5c51b" }?.value as? String
        case "transport_status":
            guard let status = object["status"] as? String, ["stable", "recovering"].contains(status) else { throw EEGRecordingError.invalidData }
            if status == "stable" && !stable { segment += 1 }
            stable = status == "stable"
        case "decode_error", "connection_error": stable = false
        default: break
        }
    }
    mutating func append(_ sample: EEGSample) -> EEGAnalysisWindow? {
        if !stable { reasons.insert("transport_unstable") }
        if configuration?.lowercased() != "018000102010" { reasons.insert("unsupported_configuration") }
        if sample.electrodesMicrovolts == nil { reasons.insert("missing_microvolts") }
        if !sample.continuous { reasons.insert("sample_discontinuity") }
        for (channel, index) in EPOCProtocol.electrodeWords {
            guard let adc = sample.electrodesADC[channel], adc.isFinite, adc >= 0, adc <= 65535,
                  adc.rounded() == adc, sample.adcWords.indices.contains(index), Double(sample.adcWords[index]) == adc else {
                reasons.insert("invalid_adc"); continue
            }
            if configuration?.lowercased() == "018000102010", let value = sample.electrodesMicrovolts?[channel],
               !value.isFinite || abs(value - adc / 7.8) > 1e-6 { reasons.insert("invalid_voltage_conversion") }
        }
        let currentSegment = stable ? segment : 0
        segments.insert(currentSegment)
        if let previous, previousSegment == currentSegment {
            if sample.index != previous.index + 1 || sample.counter != (previous.counter + 1) % 128 { reasons.insert("index_or_counter_gap") }
            if sample.receivedAt < previous.receivedAt || sample.receivedAt - previous.receivedAt > 0.5 { reasons.insert("arrival_gap") }
        }
        previous = sample; previousSegment = currentSegment
        buffer.append(sample)
        return buffer.count == 256 ? emit() : nil
    }
    mutating func finish() -> EEGAnalysisWindow? { buffer.isEmpty ? nil : emit() }
    private mutating func emit() -> EEGAnalysisWindow {
        if buffer.count != 256 { reasons.insert("partial_window") }
        if segments.count > 1 { reasons.insert("source_or_segment_boundary") }
        if segments.contains(0) { reasons.insert("missing_epoch_or_segment") }
        if buffer.count > 2 {
            let span = buffer.last!.receivedAt - buffer.first!.receivedAt
            if span <= 0 || !(120...136).contains(Double(buffer.count - 2) / span) { reasons.insert("sample_rate_not_observed_128hz") }
        }
        let result = EEGAnalysisWindow(samples: buffer, ordinal: ordinal,
                                       segment: segments.count == 1 && !segments.contains(0) ? segments.first : nil,
                                       reasons: reasons.sorted())
        ordinal += 1; buffer.removeAll(keepingCapacity: true); segments.removeAll(); reasons.removeAll()
        return result
    }
}
