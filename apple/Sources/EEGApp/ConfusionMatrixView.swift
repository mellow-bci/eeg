import SwiftUI
import EEGCore

/// A presentation of canonical evaluation counts; no recomputed predictions,
/// normalization, inferred confidence or qualification decision.
struct ConfusionMatrixView: View {
    let rows: [String: EEGLabeledEvaluation.ConfusionRow]
    @State private var expanded = true
    private var labels: [String] {
        Set(rows.keys).union(rows.values.flatMap { $0.predictedCounts.keys }).sorted()
    }
    var body: some View {
        DisclosureGroup("Candidate confusion — window counts", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Rows are declared labels; columns are experimental predicted candidates. Rejection means no prediction. Windows within a trial are correlated.")
                    .font(.caption).foregroundStyle(.secondary)
                if rows.isEmpty {
                    Text("No evaluated windows to display.").foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal) {
                        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                            GridRow {
                                header("Declared ↓ / Predicted →")
                                ForEach(labels, id: \.self) { header($0) }
                                header("Rejected")
                                header("Total windows")
                            }
                            ForEach(rows.keys.sorted(), id: \.self) { actual in
                                if let row = rows[actual] {
                                    GridRow {
                                        header(actual)
                                        ForEach(labels, id: \.self) { predicted in
                                            count(row.predictedCounts[predicted] ?? 0,
                                                  label: "Declared \(actual), predicted \(predicted)",
                                                  tint: actual == predicted ? .accentColor : .secondary)
                                        }
                                        count(row.rejectedWindows, label: "Declared \(actual), rejected with no prediction", tint: .orange)
                                        count(row.actualWindows, label: "Declared \(actual), total windows", tint: .secondary)
                                    }
                                }
                            }
                        }.padding(.vertical, 4)
                    }
                    Text("Matching labels are accented; rejected windows remain separate from every class. Counts include all evaluated windows and do not measure physiological validity or enable commands.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.vertical, 8)
        }
    }
    private func header(_ value: String) -> some View {
        Text(value).font(.caption.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 112, maxWidth: 180, alignment: .leading)
            .padding(10)
            .accessibilityAddTraits(.isHeader)
    }
    private func count(_ value: Int, label: String, tint: Color) -> some View {
        Text(value.formatted()).font(.title3.weight(.semibold).monospacedDigit())
            .frame(minWidth: 112, maxWidth: 180, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 10)
            .background(tint.opacity(value == 0 ? 0.04 : 0.12), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel(label)
            .accessibilityValue("\(value) windows")
    }
}
