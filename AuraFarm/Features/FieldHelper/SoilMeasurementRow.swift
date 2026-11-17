//
//  SoilMeasurementRow.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 11/11/26.
//

import SwiftUI

/// One recorded soil value, with where it sits against its standard under it. Tapping a row that
/// has a standard opens what that band means and what to do about it.
///
/// The band shows as a word and an icon as well as a colour, so it reads without telling the
/// colours apart. The colour and icon follow the band's tone, because "high" is good for
/// potassium and not for pH.
struct SoilMeasurementRow: View {
    let row: SoilMeasurements.Row

    var body: some View {
        if let note = row.note {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    if let effect = note.effect {
                        explanation("What this does", effect)
                    }
                    explanation("What to do", note.action)
                    Text("Placeholder guidance, not yet reviewed by an agronomist.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } label: {
                summary
            }
        } else {
            summary
        }
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(row.label)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.value)
                if let band = row.band, let note = row.note {
                    Label(band.label, systemImage: note.tone.systemImage)
                        .font(.caption)
                        .foregroundStyle(note.tone.tint)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func explanation(_ heading: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(heading)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
        }
    }
}

extension SoilTone {
    fileprivate var systemImage: String {
        switch self {
        case .good: return "checkmark.circle.fill"
        case .watch: return "eye.fill"
        case .act: return "exclamationmark.triangle.fill"
        }
    }

    fileprivate var tint: Color {
        switch self {
        case .good: return .green
        case .watch: return .orange
        case .act: return .red
        }
    }
}

#Preview {
    List {
        SoilMeasurementRow(
            row: .init(
                label: "Potassium (K)", value: "200 mg/kg", band: .high,
                note: SoilStandards.potassium.note(for: .high)))
        SoilMeasurementRow(
            row: .init(
                label: "Nitrogen (N)", value: "170 mg/kg", band: .excessive,
                note: SoilStandards.nitrogen.note(for: .excessive)))
        SoilMeasurementRow(
            row: .init(label: "Fertilizer", value: "Urea · 50 kg/ha", band: nil, note: nil))
    }
}
