import AuraFarmKit
import SwiftUI

/// What to do about a field: fertilizer doses, other actions, how far to trust it, and when to
/// test again. Written to be read out to a farmer.
struct SoilAdviceView: View {
    let advice: SoilAdvice

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("What to Do")
                    .font(.headline)
                Spacer()
                Text("Confidence: \(advice.confidence.level.label)")
                    .font(.caption.weight(.medium))
                    .padding(.vertical, 2)
                    .padding(.horizontal, 8)
                    .background(confidenceTint.opacity(0.18), in: Capsule())
            }

            if !advice.doses.isEmpty {
                doses
            }

            ForEach(Array(advice.actions.enumerated()), id: \.offset) { _, action in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.title)
                            .font(.body.weight(.medium))
                        Text(action.detail)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: Self.symbol(for: action.kind))
                        .foregroundStyle(.secondary)
                }
            }

            if !advice.retests.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Test Again")
                        .font(.subheadline.weight(.semibold))
                    bulletList(advice.retests)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("How Far to Trust This")
                    .font(.subheadline.weight(.semibold))
                bulletList(advice.confidence.reasons + advice.basis)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private var doses: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                Text("Fertilizer")
                Text("Soil")
                Text("Per hectare")
                Text("This field")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ForEach(advice.doses, id: \.fertilizer) { dose in
                GridRow {
                    Text(dose.fertilizer.name)
                        .font(.body.weight(.semibold))
                    Text("\(dose.level.label) \(dose.fertilizer.nutrient.symbol)")
                    Text("\(dose.kilogramsPerHectare, format: .number) kg")
                        .monospacedDigit()
                    if let total = dose.kilogramsForField {
                        Text("\(total, format: .number.precision(.fractionLength(0...1))) kg")
                            .monospacedDigit()
                    } else {
                        Text("Add the area")
                            .foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Text(scheduleText(for: dose))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .gridCellColumns(4)
                }
            }
        }
    }

    /// The schedule, with the actual days added once the transplanting date is known.
    private func scheduleText(for dose: FertilizerDose) -> String {
        guard !dose.dates.isEmpty else { return dose.schedule }
        let days = dose.dates
            .map { $0.formatted(.dateTime.day().month(.abbreviated)) }
            .formatted(.list(type: .and))
        return "\(dose.schedule) This season: around \(days)."
    }

    private func bulletList(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•")
                    Text(line)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var confidenceTint: Color {
        switch advice.confidence.level {
        case .low: return .orange
        case .fair: return .yellow
        case .good: return .green
        }
    }

    private static func symbol(for kind: AdviceAction.Kind) -> String {
        switch kind {
        case .soil: return "drop"
        case .organisms: return "circle.hexagongrid"
        case .testing: return "testtube.2"
        }
    }
}
