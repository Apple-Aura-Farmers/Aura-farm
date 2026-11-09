import AuraFarmKit
import SwiftUI

/// One set of NPK results in a field's list: when, from where, and the class of each nutrient.
struct NutrientTestRow: View {
    let test: NutrientTest

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(test.testedAt, format: .dateTime.day().month().year())
                    .font(.body.weight(.medium))
                Text(sourceLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ForEach(Nutrient.allCases, id: \.self) { nutrient in
                LevelBadge(symbol: nutrient.symbol, level: test.level(of: nutrient))
            }
            Text(pHLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 52, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    /// "Soil test kit · PUTS"
    private var sourceLine: String {
        let name = test.sourceName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? test.source.label : "\(test.source.label) · \(name)"
    }

    private var pHLabel: String {
        guard let pH = test.pH else { return "pH –" }
        return "pH \(pH.formatted(.number.precision(.fractionLength(1))))"
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
            .help(level == nil ? "Not tested" : "\(level?.label ?? "") \(symbol)")
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
