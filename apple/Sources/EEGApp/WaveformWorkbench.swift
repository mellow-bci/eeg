import SwiftUI
import EEGCore
import Charts

/// Exact source indices and original samples, never re-sampled or display-centered.
/// Nil callback means there is no current source to analyze.
struct WaveformSelection: Equatable {
    let sourceStartIndex: Int
    let sourceEndIndex: Int
    let visibleStartIndex: Int
    let visibleEndIndex: Int
    let selectedStartIndex: Int
    let selectedEndIndex: Int
    let selectedChannel: String
    let selectedSamples: [EEGSample]
    let frozen: Bool
}

struct WaveformWorkbench: View {
    let samples: [EEGSample]
    var title = "Signals"
    var onSelectionChange: (WaveformSelection?) -> Void = { _ in }
    @State private var channelsShown = Set(EEGRecordingStore.channels)
    @State private var span = 10.0
    @State private var channelHeight = 56.0
    @State private var unit = "ADC"
    @State private var amplitude = 0.0
    @State private var centered = true
    @State private var frozenSamples: [EEGSample]?
    @State private var viewport: ClosedRange<Int>?
    @State private var analysisRange: ClosedRange<Int>?
    @State private var cursorOffset: Int?
    @State private var detailChannel = "O1"
    @State private var chartTime: Double?
    @State private var inspectorExpanded = false
    @State private var startText = ""
    @State private var endText = ""
    @State private var navigationError: String?
    private var source: [EEGSample] { frozenSamples ?? samples }
    private var calibrated: Bool { !source.isEmpty && source.allSatisfy { $0.electrodesMicrovolts != nil } }
    private var actualUnit: String { unit == "µV" && calibrated ? "µV" : "ADC" }
    private var channels: [String] { EEGRecordingStore.channels.filter { channelsShown.contains($0) } }
    private func clamp(_ range: ClosedRange<Int>) -> ClosedRange<Int> {
        let last = max(0, source.count - 1)
        return min(last, max(0, range.lowerBound))...min(last, max(0, range.upperBound))
    }
    private var visibleRange: ClosedRange<Int> {
        if let viewport = viewport { return clamp(viewport) }
        guard let end = source.last else { return 0...0 }
        let start = source.firstIndex { $0.receivedAt >= end.receivedAt - span } ?? 0
        return start...max(start, source.count - 1)
    }
    private var selectedRange: ClosedRange<Int> { clamp(analysisRange ?? max(0, source.count - 256)...max(0, source.count - 1)) }
    private var visible: [EEGSample] { source.isEmpty ? [] : Array(source[visibleRange]) }
    private var selectedSamples: [EEGSample] { source.isEmpty ? [] : Array(source[selectedRange]) }
    private var cursor: EEGSample? { source.isEmpty ? nil : source[min(source.count - 1, max(0, cursorOffset ?? selectedRange.upperBound))] }
    private var rangeTimes: ClosedRange<Double>? {
        guard let first = selectedSamples.first, let last = selectedSamples.last, first.receivedAt <= last.receivedAt else { return nil }
        return first.receivedAt...last.receivedAt
    }
    private var selection: WaveformSelection? {
        guard let first = source.first, let last = source.last, let start = selectedSamples.first, let end = selectedSamples.last,
              let visibleFirst = visible.first, let visibleLast = visible.last else { return nil }
        return WaveformSelection(sourceStartIndex: first.index, sourceEndIndex: last.index,
                                 visibleStartIndex: visibleFirst.index, visibleEndIndex: visibleLast.index,
                                 selectedStartIndex: start.index, selectedEndIndex: end.index,
                                 selectedChannel: detailChannel, selectedSamples: selectedSamples, frozen: frozenSamples != nil)
    }
    // A scalar key prevents comparing/copying all samples on every view evaluation.
    private var selectionKey: String {
        "\(source.first?.index ?? -1):\(source.last?.index ?? -1):\(source.first?.receivedAt ?? -1):\(visibleRange):\(selectedRange):\(detailChannel):\(frozenSamples != nil)"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Text("\(source.count.formatted()) loaded · \(channels.count) channels").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button(action: toggleFreeze) { Label(frozenSamples == nil ? "Freeze" : "Follow source", systemImage: frozenSamples == nil ? "pause" : "play") }.disabled(samples.isEmpty)
                    .help("Selection freezes the displayed snapshot. Recording continues independently.")
            }.padding(.bottom, 12)
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 16) { displayControls }.padding(.vertical, 4) }.padding(.bottom, 8)
            if source.isEmpty {
                ContentUnavailableView("No source loaded", systemImage: "waveform.path", description: Text("Connect a headset or open a recording. The workstation displays original samples only.")).frame(minHeight: 280)
            } else {
                overview
                viewportNavigation.padding(.vertical, 8)
                if channels.isEmpty { ContentUnavailableView("Choose channels", systemImage: "line.3.horizontal.decrease") }
                else { mainTraces }
                timeAxis.padding(.top, 5).padding(.bottom, 10)
                selectionControls
                if inspectorExpanded { sampleInspector.padding(.top, 12) }
            }
            Text("Receipt-time axis · \(centered ? "visible channel means removed for display" : "absolute values") · common \(amplitude == 0 ? "auto" : "fixed") amplitude · gaps break traces · fixed-scale overflow clips visually. Stored and selected samples are unchanged.")
                .font(.caption2).foregroundStyle(.secondary).padding(.top, 10)
        }
        .onChange(of: selectionKey, initial: true) { _, _ in
            startText = selectedSamples.first.map { String($0.index) } ?? ""
            endText = selectedSamples.last.map { String($0.index) } ?? ""
            onSelectionChange(selection)
        }
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("LOADED SOURCE").font(.caption2.weight(.semibold))
                Text("#\(source.first?.index ?? 0)–\(source.last?.index ?? 0)").font(.caption2.monospacedDigit())
                Spacer()
                Text("Drag to navigate · orange = analysis range").font(.caption2)
            }.foregroundStyle(.secondary)
            GeometryReader { geometry in
                SignalCanvas(samples: source, channels: channels.isEmpty ? [detailChannel] : channels, unit: actualUnit, amplitude: 0,
                             centered: true, cursorTime: nil, selectionTimes: rangeTimes, highlightedChannel: nil, compact: true)
                    .overlay {
                        if let first = source.first, let last = source.last, let vFirst = visible.first, let vLast = visible.last {
                            let left = 44.0, width = max(1, geometry.size.width - left - 8)
                            let duration = max(0.001, last.receivedAt - first.receivedAt)
                            let x = left + (vFirst.receivedAt - first.receivedAt) / duration * width
                            let selectedWidth = max(3, (vLast.receivedAt - vFirst.receivedAt) / duration * width)
                            Rectangle().stroke(Color.accentColor, lineWidth: 2).background(Color.accentColor.opacity(0.06))
                                .frame(width: selectedWidth).offset(x: x).frame(maxWidth: .infinity, alignment: .leading).allowsHitTesting(false)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 3).onChanged { drag in
                        freezeSnapshot()
                        let a = offset(at: drag.startLocation.x, width: geometry.size.width, within: 0...max(0, source.count - 1))
                        let b = offset(at: drag.location.x, width: geometry.size.width, within: 0...max(0, source.count - 1))
                        viewport = min(a, b)...max(a, b)
                    })
            }.frame(height: 86).background(.quaternary.opacity(0.15)).clipped()
                .accessibilityLabel("Overview of all loaded samples. Use navigation buttons to pan or the zoom menu to change the visible range.")
        }
    }
    private var viewportNavigation: some View {
        HStack(spacing: 10) {
            Button { pan(-1) } label: { Image(systemName: "chevron.left") }.help("Pan one half-window earlier").accessibilityLabel("Pan earlier").disabled(visibleRange.lowerBound == 0)
            Button { pan(1) } label: { Image(systemName: "chevron.right") }.help("Pan one half-window later").accessibilityLabel("Pan later").disabled(visibleRange.upperBound >= source.count - 1)
            Menu { ForEach([1.0, 2, 5, 10], id: \.self) { seconds in Button("\(Int(seconds)) seconds") { zoom(seconds) } }; Button("Entire loaded source") { viewport = 0...max(0, source.count - 1) } } label: { Label("Zoom", systemImage: "plus.magnifyingglass") }
            Button("Fit selection") { viewport = selectedRange }
            Spacer()
            Text("VIEW #\(visible.first?.index ?? 0)–\(visible.last?.index ?? 0)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            if frozenSamples != nil { Image(systemName: "pause.fill").foregroundStyle(.orange).help("Frozen snapshot; acquisition continues") }
        }.controlSize(.small)
    }
    private var mainTraces: some View {
        GeometryReader { geometry in
            SignalCanvas(samples: visible, channels: channels, unit: actualUnit, amplitude: amplitude, centered: centered,
                         cursorTime: cursor?.receivedAt, selectionTimes: rangeTimes, highlightedChannel: detailChannel, compact: false)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 3).onChanged { drag in
                    freezeSnapshot()
                    let a = offset(at: drag.startLocation.x, width: geometry.size.width, within: visibleRange)
                    let b = offset(at: drag.location.x, width: geometry.size.width, within: visibleRange)
                    analysisRange = min(a, b)...max(a, b); cursorOffset = b
                    chooseChannel(y: drag.startLocation.y, height: geometry.size.height)
                })
                .onTapGesture(coordinateSpace: .local) { point in
                    freezeSnapshot(); cursorOffset = offset(at: point.x, width: geometry.size.width, within: visibleRange)
                    chooseChannel(y: point.y, height: geometry.size.height)
                }
        }.frame(height: max(180, CGFloat(channels.count) * channelHeight + 12)).clipped()
            .accessibilityLabel("\(channels.count) synchronized EEG traces in \(actualUnit). Drag a range to select original samples for analysis. Exact selection controls follow.")
    }
    private var timeAxis: some View {
        HStack {
            Text(time(visible.first?.receivedAt)); Spacer(); Text("Receipt time / seconds"); Spacer(); Text(time(visible.last?.receivedAt))
        }.font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
    }
    private var selectionControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "selection.pin.in.out").foregroundStyle(.orange)
                Text("Analysis range").font(.callout.weight(.semibold))
                Text("\(selectedSamples.count) samples · \(time(selectedSamples.first?.receivedAt))–\(time(selectedSamples.last?.receivedAt)) s").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button { inspectorExpanded.toggle() } label: { Image(systemName: inspectorExpanded ? "rectangle.bottomthird.inset.filled" : "rectangle.bottomthird.inset") }.accessibilityLabel("Toggle exact sample inspector")
            }
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 12) { exactSelectionControls }.padding(.vertical, 2) }
            HStack {
                TextField("Start sample #", text: $startText).frame(maxWidth: 140).accessibilityLabel("Exact selection start sample index").onSubmit(applyTypedRange)
                Text("through").foregroundStyle(.secondary)
                TextField("End sample #", text: $endText).frame(maxWidth: 140).accessibilityLabel("Exact selection end sample index").onSubmit(applyTypedRange)
                Button("Apply") { applyTypedRange() }
                Spacer()
            }.textFieldStyle(.roundedBorder).controlSize(.small)
            if let navigationError = navigationError { Text(navigationError).font(.caption).foregroundStyle(.orange) }
        }.padding(10).background(.orange.opacity(0.06))
    }
    @ViewBuilder private var exactSelectionControls: some View {
        Picker("Channel", selection: $detailChannel) { ForEach(EEGRecordingStore.channels, id: \.self) { Text($0).tag($0) } }.frame(width: 145)
        Stepper("Start #\(selectedSamples.first?.index ?? 0)", onIncrement: { moveBoundary(start: true, step: 1) }, onDecrement: { moveBoundary(start: true, step: -1) }).fixedSize()
        Stepper("End #\(selectedSamples.last?.index ?? 0)", onIncrement: { moveBoundary(start: false, step: 1) }, onDecrement: { moveBoundary(start: false, step: -1) }).fixedSize()
        Button("256 at cursor") {
            freezeSnapshot(); let end = min(source.count - 1, max(255, cursorOffset ?? selectedRange.upperBound))
            analysisRange = max(0, end - 255)...end
        }.disabled(source.count < 256).help("Select the 256 original samples ending at the cursor, or the first available full window")
        Button("Visible range") { freezeSnapshot(); analysisRange = visibleRange }
    }
    private var sampleInspector: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(detailChannel) · exact signal").font(.callout.weight(.semibold))
                Spacer()
                if let cursor = cursor { Text("CURSOR #\(cursor.index) · counter \(cursor.counter) · \(time(cursor.receivedAt)) s").font(.caption2.monospacedDigit()).textSelection(.enabled) }
            }
            SignalDetailChart(samples: visible, channel: detailChannel, unit: actualUnit, selectedTime: $chartTime)
                .frame(height: 240)
                .onChange(of: chartTime) { _, time in
                    guard let time = time, let offset = source.indices.min(by: { abs(source[$0].receivedAt - time) < abs(source[$1].receivedAt - time) }) else { return }
                    freezeSnapshot(); cursorOffset = offset
                }
            HStack {
                Button { moveCursor(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous exact sample")
                Slider(value: Binding(get: { Double(cursorOffset ?? selectedRange.upperBound) }, set: { freezeSnapshot(); cursorOffset = Int($0.rounded()) }), in: 0...Double(max(1, source.count - 1)), step: 1).accessibilityLabel("Exact sample position")
                Button { moveCursor(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next exact sample")
            }.controlSize(.small)
            if let cursor = cursor {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88))], alignment: .leading, spacing: 8) {
                    ForEach(channels, id: \.self) { channel in
                        let value = actualUnit == "µV" ? cursor.electrodesMicrovolts?[channel] : cursor.electrodesADC[channel]
                        VStack(alignment: .leading, spacing: 2) {
                            Text(channel).font(.caption2.weight(.semibold)).foregroundStyle(channel == detailChannel ? Color.accentColor : .secondary)
                            Text(value.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "—").font(.caption.monospacedDigit())
                        }.accessibilityElement(children: .combine).accessibilityValue(actualUnit)
                    }
                }
            }
        }
    }
    @ViewBuilder private var displayControls: some View {
        Menu {
            Button("All channels") { channelsShown = Set(EEGRecordingStore.channels) }
            Button("Occipital pair") { channelsShown = ["O1", "O2"] }
            Divider()
            ForEach(EEGRecordingStore.channels, id: \.self) { channel in Toggle(channel, isOn: Binding(get: { channelsShown.contains(channel) }, set: { if $0 { channelsShown.insert(channel) } else { channelsShown.remove(channel) } })) }
        } label: { Label("Channels", systemImage: "line.3.horizontal.decrease") }
        Picker("Units", selection: $unit) { Text("ADC").tag("ADC"); Text("µV").tag("µV").disabled(!calibrated) }.frame(width: 125).onChange(of: unit) { _, _ in amplitude = 0 }
        Picker("Common scale", selection: $amplitude) {
            Text("Auto").tag(0.0)
            ForEach(actualUnit == "µV" ? [25.0, 50, 100, 250] : [100.0, 250, 500, 2000, 16000], id: \.self) { Text("±\(Int($0))").tag($0) }
        }.frame(width: 200)
        Picker("Channel height", selection: $channelHeight) {
            Text("Compact").tag(29.0); Text("Comfortable").tag(56.0); Text("Expanded").tag(88.0)
        }.frame(width: 230)
        Toggle("Center traces", isOn: $centered).toggleStyle(.switch).controlSize(.small)
    }
    private func applyTypedRange() {
        guard let start = Int(startText), let end = Int(endText),
              let lower = source.firstIndex(where: { $0.index == start }),
              let upper = source.firstIndex(where: { $0.index == end }), lower <= upper else {
            navigationError = "Enter an ordered range of sample indices present in the loaded source."
            return
        }
        freezeSnapshot(); analysisRange = lower...upper; cursorOffset = upper; navigationError = nil
    }
    private func freezeSnapshot() { if frozenSamples == nil { frozenSamples = samples } }
    private func toggleFreeze() {
        if frozenSamples == nil { freezeSnapshot() }
        else { frozenSamples = nil; viewport = nil; analysisRange = nil; cursorOffset = nil }
    }
    private func moveCursor(_ step: Int) { freezeSnapshot(); cursorOffset = min(max(0, (cursorOffset ?? selectedRange.upperBound) + step), max(0, source.count - 1)) }
    private func moveBoundary(start: Bool, step: Int) {
        freezeSnapshot(); let current = selectedRange
        if start { analysisRange = min(current.upperBound, max(0, current.lowerBound + step))...current.upperBound }
        else { analysisRange = current.lowerBound...max(current.lowerBound, min(source.count - 1, current.upperBound + step)) }
    }
    private func pan(_ direction: Int) {
        freezeSnapshot(); let range = visibleRange; let length = range.count
        let lower = max(0, min(source.count - length, range.lowerBound + direction * max(1, length / 2)))
        viewport = lower...(lower + length - 1)
    }
    private func zoom(_ seconds: Double) {
        freezeSnapshot(); span = seconds
        let center = cursorOffset ?? (visibleRange.lowerBound + visibleRange.upperBound) / 2
        guard !source.isEmpty else { return }
        let t = source[min(source.count - 1, center)].receivedAt
        let lower = source.firstIndex { $0.receivedAt >= t - seconds / 2 } ?? 0
        let upper = source.lastIndex { $0.receivedAt <= t + seconds / 2 } ?? source.count - 1
        viewport = min(lower, upper)...max(lower, upper)
    }
    private func offset(at x: Double, width: Double, within range: ClosedRange<Int>) -> Int {
        guard !source.isEmpty else { return 0 }
        let safe = clamp(range), first = source[safe.lowerBound].receivedAt, last = source[safe.upperBound].receivedAt
        let fraction = min(1, max(0, (x - 44) / max(1, width - 52)))
        let target = first + fraction * (last - first)
        return safe.min { abs(source[$0].receivedAt - target) < abs(source[$1].receivedAt - target) } ?? safe.lowerBound
    }
    private func chooseChannel(y: Double, height: Double) {
        guard !channels.isEmpty else { return }
        detailChannel = channels[min(channels.count - 1, max(0, Int(y / max(1, height) * Double(channels.count))))]
    }
    private func time(_ value: Double?) -> String { value?.formatted(.number.precision(.fractionLength(3))) ?? "—" }
}

private struct SignalCanvas: View {
    let samples: [EEGSample]
    let channels: [String]
    let unit: String
    let amplitude: Double
    let centered: Bool
    let cursorTime: Double?
    let selectionTimes: ClosedRange<Double>?
    let highlightedChannel: String?
    let compact: Bool
    var body: some View {
        Canvas { context, size in
            guard let first = samples.first, let last = samples.last else { return }
            let left = 44.0, width = max(1, size.width - left - 8)
            let duration = max(0.001, last.receivedAt - first.receivedAt)
            let rowHeight = (size.height - 12) / Double(channels.count)
            let values = channels.map { channel in samples.map { unit == "µV" ? $0.electrodesMicrovolts?[channel] : $0.electrodesADC[channel] } }
            let means = values.map { row -> Double in let valid = row.compactMap { $0 }; return centered && !valid.isEmpty ? valid.reduce(0, +) / Double(valid.count) : 0 }
            let extent = amplitude > 0 ? amplitude : max(1, values.enumerated().flatMap { row, vals in vals.compactMap { $0.map { abs($0 - means[row]) } } }.max() ?? 1)
            if let selection = selectionTimes {
                let x1 = max(left, left + (selection.lowerBound - first.receivedAt) / duration * width)
                let x2 = min(size.width - 8, left + (selection.upperBound - first.receivedAt) / duration * width)
                if x2 >= x1 {
                    context.fill(Path(CGRect(x: x1, y: 0, width: max(1, x2 - x1), height: size.height)), with: .color(.orange.opacity(compact ? 0.18 : 0.09)))
                    var edges = Path(); edges.move(to: CGPoint(x: x1, y: 0)); edges.addLine(to: CGPoint(x: x1, y: size.height)); edges.move(to: CGPoint(x: x2, y: 0)); edges.addLine(to: CGPoint(x: x2, y: size.height))
                    context.stroke(edges, with: .color(.orange.opacity(0.6)), lineWidth: 1)
                }
            }
            var grid = Path()
            for i in 0...10 { let x = left + Double(i) * width / 10; grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height)) }
            context.stroke(grid, with: .color(.secondary.opacity(0.14)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            for (row, channel) in channels.enumerated() {
                let baseline = Double(row) * rowHeight + rowHeight / 2
                if channel == highlightedChannel {
                    context.fill(Path(CGRect(x: 0, y: Double(row) * rowHeight, width: size.width, height: rowHeight)), with: .color(.teal.opacity(0.055)))
                }
                if !compact { context.draw(Text(channel).font(.system(size: 11, weight: channel == highlightedChannel ? .bold : .medium, design: .monospaced)).foregroundColor(channel == highlightedChannel ? .teal : .secondary), at: CGPoint(x: 18, y: baseline)) }
                var axis = Path(); axis.move(to: CGPoint(x: left, y: baseline)); axis.addLine(to: CGPoint(x: size.width, y: baseline))
                context.stroke(axis, with: .color(.secondary.opacity(0.12)), lineWidth: 1)
                var path = Path(); var begun = false
                for (index, sample) in samples.enumerated() {
                    guard let value = values[row][index], value.isFinite else { begun = false; continue }
                    let x = left + (sample.receivedAt - first.receivedAt) / duration * width
                    let scaled = max(-1, min(1, (value - means[row]) / extent))
                    let point = CGPoint(x: x, y: baseline - scaled * rowHeight * 0.43)
                    if !begun || !sample.continuous || (index > 0 && (sample.index != samples[index - 1].index + 1 || sample.receivedAt < samples[index - 1].receivedAt)) { path.move(to: point); begun = true } else { path.addLine(to: point) }
                }
                context.stroke(path, with: .color(row.isMultiple(of: 2) ? .teal : .cyan), lineWidth: compact ? 0.6 : 1.1)
            }
            if let cursorTime = cursorTime, cursorTime >= first.receivedAt, cursorTime <= last.receivedAt {
                let x = left + (cursorTime - first.receivedAt) / duration * width
                var path = Path(); path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(.orange), lineWidth: 1)
            }
            if !compact { context.draw(Text("±\(extent.formatted(.number.precision(.fractionLength(1)))) \(unit)").font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary), at: CGPoint(x: size.width - 5, y: 4), anchor: .topTrailing) }
        }
    }
}


/// Semantic single-channel detail complements the dense Canvas overview.
private struct SignalDetailChart: View {
    let samples: [EEGSample]
    let channel: String
    let unit: String
    @Binding var selectedTime: Double?
    private struct Point: Identifiable { let id: Int; let time: Double; let value: Double; let segment: Int }
    private var points: [Point] {
        var segment = 0
        return samples.enumerated().compactMap { offset, sample in
            if !sample.continuous || (offset > 0 && (sample.index != samples[offset - 1].index + 1 || sample.receivedAt < samples[offset - 1].receivedAt)) { segment += 1 }
            guard let value = unit == "µV" ? sample.electrodesMicrovolts?[channel] : sample.electrodesADC[channel] else { segment += 1; return nil }
            return Point(id: sample.index, time: sample.receivedAt, value: value, segment: segment)
        }
    }
    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(x: .value("Receipt time (s)", point.time), y: .value(unit, point.value), series: .value("Continuous segment", point.segment))
                    .foregroundStyle(.teal).lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            if let selectedTime = selectedTime { RuleMark(x: .value("Selected receipt time", selectedTime)).foregroundStyle(.orange) }
        }
        .chartXSelection(value: $selectedTime)
        .chartXAxisLabel("Receipt time (s)")
        .chartYAxisLabel("\(channel) · \(unit), absolute")
        .chartYScale(domain: .automatic(includesZero: false))
        .accessibilityLabel("Absolute \(channel) samples in \(unit). Discontinuities separate line segments.")
    }
}
