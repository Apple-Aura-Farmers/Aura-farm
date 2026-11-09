import AuraFarmKit
import SwiftUI

/// One set of NPK results in a field's list: when, from where, and the class of each nutrient.
struct NutrientTestRow: View {
    let test: NutrientTest

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(test.testedAt, format: .dateTime.day().month().year())
                    .font(.body.weight(.medium))
                Spacer()
                Text(sourceLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                ForEach(Nutrient.allCases, id: \.self) { nutrient in
                    LevelBadge(symbol: nutrient.symbol, level: test.level(of: nutrient))
                }
                Spacer()
                Text(pHLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    /// "Soil test kit · PUTS"
    private var sourceLine: String {
        let name = test.sourceName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? test.source.label : "\(test.source.label) · \(name)"
    }

    /// "pH 6.2", with organic carbon after it when it was measured: "pH 6.2 · C 1.8%"
    private var pHLabel: String {
        var label = test.pH.map { "pH \($0.formatted(.number.precision(.fractionLength(1))))" } ?? "pH –"
        if let carbon = test.organicCarbonPercent {
            label += " · C \(carbon.formatted(.number.precision(.fractionLength(1))))%"
        }
        return label
    }
}

/// "N Low", with a colour that only helps tell the classes apart: the class is always written.
private struct LevelBadge: View {
    let symbol: String
    let level: NutrientLevel?

    var body: some View {
        Text("\(symbol) \(level?.label ?? "–")")
            .font(.caption.weight(.medium))
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background(tint.opacity(0.18), in: Capsule())
    }

    private var tint: Color {
        switch level {
        case .low: return .orange
        case .medium: return .blue
        case .high: return .green
        case nil: return .gray
        }
    }
}
