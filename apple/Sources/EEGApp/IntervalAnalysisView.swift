import SwiftUI
import Charts
import EEGCore

/// Shared analysis for the exact selection emitted by the waveform workbench.
/// Computed results never mutate or replace the selected source measurements.
struct IntervalAnalysisView: View {
    let selection: WaveformSelection?
    @State private var result: EEGIntervalAnalysisResult?
    @State private var error: String?
    @State private var busy = false
    @State private var selectedFrequency: Double?
    private struct Bin: Identifiable {
        let id: Int; let frequency: Double; let density: Double
    }
    private struct Tile: Identifiable {
        let id: Int; let window: Int; let frequency: Double; let decibels: Double
    }
    private var analysisKey: String {
        guard let s = selection else { return "none" }
        return "\(s.selectedStartIndex):\(s.selectedEndIndex):\(s.selectedChannel):\(s.selectedSamples.first?.receivedAt ?? -1):\(s.selectedSamples.last?.receivedAt ?? -1)"
    }
    private var bins: [Bin] {
        guard let r = result, let mean = r.meanDensityMicrovoltsSquaredPerHz else { return [] }
        return zip(r.frequenciesHz, mean).enumerated().filter { $0.element.0 <= 40 }.map {
            Bin(id: $0.offset, frequency: $0.element.0, density: 10 * log10(max($0.element.1, 1e-20)))
        }
    }
    private var tiles: [Tile] {
        guard let r = result else { return [] }
        return r.windows.enumerated().flatMap { position, window -> [Tile] in
            guard let psd = window.densityMicrovoltsSquaredPerHz else { return [] }
            return zip(r.frequenciesHz, psd).enumerated().filter { $0.element.0 <= 40 }.map {
                Tile(id: position * r.frequenciesHz.count + $0.offset, window: position,
                     frequency: $0.element.0, decibels: 10 * log10(max($0.element.1, 1e-20)))
            }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Selection analysis", systemImage: "waveform.path").font(.headline)
                if let selection = selection {
                    Text("\(selection.selectedChannel) · \(selection.selectedSamples.count.formatted()) samples").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
            }
            if let r = result {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) { spectrum.frame(minWidth: 330); spectrogram.frame(minWidth: 330) }
                    VStack(spacing: 24) { spectrum; spectrogram }
                }
                Text("\(r.acceptedWindowCount) structurally valid windows · \(r.rejectedWindowCount) rejected · 256 samples/window · 128-sample hop").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Text("\(r.flaggedWindowCount) windows carry artifact flags · \(r.trailingUncoveredSampleCount) trailing samples outside complete windows").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Text("Mean includes structurally valid windows. Artifact flags are observations, not physiological validation. Blank spectrogram columns indicate rejected windows; analysis never interpolates gaps.").font(.caption).foregroundStyle(.secondary)
                if r.rejectedWindowCount > 0 {
                    DisclosureGroup("Rejected windows") {
                        ForEach(Array(r.windows.enumerated()).filter { !$0.element.accepted }, id: \.offset) { _, window in
                            Text("Samples \(window.startIndex)–\(window.endIndex): \(window.rejectionReason ?? "Unavailable")").font(.caption.monospaced())
                        }
                    }
                }
            } else {
                Text(error ?? "Select at least 256 samples in the waveform to analyze that interval.").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
            }
        }
        .padding(16)
        .background(.background)
        .overlay(alignment: .top) { Divider() }
        .task(id: analysisKey) { await analyze() }
    }
    private var spectrum: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mean spectral density").font(.subheadline.weight(.semibold))
            Chart {
                ForEach(bins) { bin in
                    LineMark(x: .value("Frequency", bin.frequency), y: .value("dB re 1 µV²/Hz", bin.density)).foregroundStyle(.teal)
                }
                if let frequency = selectedFrequency, let bin = bins.min(by: { abs($0.frequency - frequency) < abs($1.frequency - frequency) }) {
                    RuleMark(x: .value("Frequency", bin.frequency)).foregroundStyle(.secondary)
                    PointMark(x: .value("Frequency", bin.frequency), y: .value("Density", bin.density)).foregroundStyle(.teal)
                }
            }
            .chartXScale(domain: 0...40).chartXAxisLabel("Frequency (Hz)").chartYAxisLabel("dB re 1 µV²/Hz")
            .chartXSelection(value: $selectedFrequency).frame(height: 190)
            .accessibilityLabel("Mean spectral density for the selected interval")
        }
    }
    private var spectrogram: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spectrogram · selected interval").font(.subheadline.weight(.semibold))
            Chart(tiles) { tile in
                RectangleMark(xStart: .value("Window start", Double(tile.window)), xEnd: .value("Window end", Double(tile.window + 1)),
                              yStart: .value("Frequency lower", max(0, tile.frequency - 0.25)), yEnd: .value("Frequency upper", min(40, tile.frequency + 0.25)))
                    .foregroundStyle(by: .value("dB re 1 µV²/Hz", tile.decibels))
                    .accessibilityLabel("Window \(tile.window + 1), \(tile.frequency.formatted()) Hz")
                    .accessibilityValue("\(tile.decibels.formatted()) dB re 1 microvolt squared per hertz")
            }
            .chartForegroundStyleScale(range: Gradient(colors: [.indigo, .blue, .cyan, .yellow]))
            .chartXScale(domain: 0...Double(max(1, result?.windows.count ?? 0)))
            .chartYScale(domain: 0...40).chartXAxisLabel("Window ordinal · nominal 1 s hop").chartYAxisLabel("Hz")
            .frame(height: 190)
        }
    }
    @MainActor private func analyze() async {
        busy = false; result = nil; error = nil
        guard let selected = selection, selected.selectedSamples.count >= 256 else { return }
        busy = true
        let outcome = await Task.detached(priority: .userInitiated) {
            Result { try EEGIntervalAnalysis.analyze(samples: selected.selectedSamples, channel: selected.selectedChannel) }
        }.value
        guard !Task.isCancelled else { return }
        busy = false
        switch outcome { case .success(let value): result = value; case .failure(let failure): error = failure.localizedDescription }
    }
}
