import SwiftUI
import Charts
import EEGCore

struct SpectrumAnalysisView: View {
    @EnvironmentObject var model: AcquisitionModel
    @State private var channel = "O1"
    @State private var result: EEGSpectrumResult?
    @State private var failure: String?
    @State private var computing = false
    @State private var logarithmic = true
    @State private var maximumFrequency = 45.0
    @State private var selectedFrequency: Double?
    @State private var windowEnd: Int?
    private struct Bin: Identifiable { let frequency: Double; let density: Double; var id: Double { frequency } }
    private var bins: [Bin] {
        guard let result = result else { return [] }
        return zip(result.frequenciesHz, result.densityMicrovoltsSquaredPerHz).filter { $0.0 <= maximumFrequency }.map {
            Bin(frequency: $0.0, density: logarithmic ? 10 * log10(max(1e-20, $0.1)) : $0.1)
        }
    }
    private var selectedBin: Bin? { guard let frequency = selectedFrequency else { return nil }; return bins.min { abs($0.frequency - frequency) < abs($1.frequency - frequency) } }
    private var refreshKey: String { "\(channel)-\(model.samples.last.map { $0.index / 64 } ?? -1)-\(model.selectedRecording?.path ?? "live")-\(model.transportStable)-\(model.playback)" }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 6) { Text("Frequency explorer").font(.largeTitle.bold()); Text("A two-second window from the actual signal. No inferred mental-state scores.").foregroundStyle(.secondary) }
                Spacer(); if computing { ProgressView().controlSize(.small) }
            }
            Panel(title: "Analysis source") {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) { options }
                    VStack(alignment: .leading, spacing: 14) { options }
                }
                Label(model.playback ? "Recorded window · transport provenance not yet reconstructed" : model.transportStable ? "Live transport stabilized" : "Waiting for stable live transport", systemImage: model.playback ? "doc.text.magnifyingglass" : "waveform.path")
                    .font(.callout).foregroundStyle(.secondary)
                Text("128 Hz configuration · 256 samples · linear detrend · periodic Hann window · one-sided PSD").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            if let result = result {
                Panel(title: "\(result.channel) · power spectral density") {
                    densityChart
                    .chartXScale(domain: 0...maximumFrequency)
                    .chartXAxisLabel("Frequency (Hz)")
                    .chartYAxisLabel(logarithmic ? "dB re 1 µV²/Hz" : "µV²/Hz")
                    .chartXSelection(value: $selectedFrequency)
                    .frame(height: 300)
                    .accessibilityLabel("\(result.channel) power spectral density from 256 actual samples")
                    HStack {
                        if let bin = selectedBin { Text("\(bin.frequency.formatted(.number.precision(.fractionLength(1)))) Hz · \(bin.density.formatted(.number.precision(.fractionLength(3)))) \(logarithmic ? "dB re 1 µV²/Hz" : "µV²/Hz")").font(.caption.monospacedDigit()) }
                        else { Text("Select a frequency to inspect its density.").font(.caption).foregroundStyle(.secondary) }
                        Spacer(); Text("Window ends at sample \(windowEnd ?? 0)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190))], spacing: 12) {
                    Metric(title: "Detrended RMS", value: result.detrendedRMSMicrovolts.formatted(.number.precision(.fractionLength(2))) + " µV")
                    Metric(title: "Peak-to-peak", value: result.peakToPeakMicrovolts.formatted(.number.precision(.fractionLength(2))) + " µV")
                    Metric(title: "Artifact observations", value: String(result.artifactFlags.count))
                }
                Panel(title: "Integrated band power") {
                    Chart(result.bands, id: \.name) { band in BarMark(x: .value("Band", band.name), y: .value("Power (µV²)", band.powerMicrovoltsSquared)).foregroundStyle(.teal.gradient).cornerRadius(4) }
                        .chartYAxisLabel("µV²").frame(height: 190)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], alignment: .leading, spacing: 16) {
                        ForEach(result.bands, id: \.name) { band in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(band.name.capitalized).font(.callout.weight(.semibold))
                                Text("\(band.lowHz.formatted())–<\(band.highHz.formatted()) Hz").font(.caption).foregroundStyle(.secondary)
                                Text(band.powerMicrovoltsSquared.formatted(.number.precision(.fractionLength(3))) + " µV²").font(.caption.monospacedDigit())
                            }.accessibilityElement(children: .combine)
                        }
                    }
                }
                Panel(title: "Interpretation boundary") {
                    if result.artifactFlags.isEmpty { Text("No configured artifact threshold triggered in this channel window.") }
                    else { ForEach(result.artifactFlags, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) } }
                    Text("These are descriptive measurements of \(channel), not physiological readiness, validated contact quality, attention, stress or emotion. Thresholds remain unvalidated.").font(.callout).foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView("Spectrum unavailable", systemImage: "waveform.path", description: Text(failure ?? "Connect a headset with stable transport or review a calibrated recording containing at least 256 continuous samples."))
                    .frame(minHeight: 320)
            }
        }.task(id: refreshKey) { await compute() }
    }
    private var densityChart: some View {
        Chart {
            ForEach(bins) { bin in
                LineMark(x: .value("Frequency (Hz)", bin.frequency), y: .value("Power density", bin.density))
                    .foregroundStyle(.teal).lineStyle(StrokeStyle(lineWidth: 2))
            }
            if let bin = selectedBin {
                RuleMark(x: .value("Frequency", bin.frequency)).foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
            }
        }
    }
    @ViewBuilder private var options: some View {
        Picker("Channel", selection: $channel) { ForEach(EEGRecordingStore.channels, id: \.self) { Text($0).tag($0) } }.frame(maxWidth: 200)
        Picker("Frequency range", selection: $maximumFrequency) { Text("0–30 Hz").tag(30.0); Text("0–45 Hz").tag(45.0); Text("0–64 Hz").tag(64.0) }.frame(maxWidth: 240)
        Toggle("Log density", isOn: $logarithmic).toggleStyle(.switch).fixedSize()
    }
    @MainActor private func compute() async {
        computing = false; result = nil; failure = nil
        guard model.playback || model.transportStable else { result = nil; failure = "Live analysis waits for stable transport. Receipt of samples alone is insufficient."; return }
        let snapshot = Array(model.samples.suffix(256)); let selected = channel
        guard snapshot.count == 256 else { result = nil; failure = "This page contains fewer than 256 samples."; return }
        computing = true
        let outcome = await Task.detached(priority: .userInitiated) { Result { try EEGSpectrum.analyze(samples: snapshot, channel: selected) } }.value
        guard !Task.isCancelled else { return }
        computing = false
        switch outcome {
        case .success(let value): result = value; failure = nil; windowEnd = snapshot.last?.index
        case .failure(let error): result = nil; failure = error.localizedDescription
        }
    }
}
