//
//  SoilMeasurementRow.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 11/11/26.
//

import SwiftUI

/// One recorded soil value, with where it sits against its standard under it, and a line on what
/// this reading may mean. What to do about it is in "What to do next", not here.
///
/// The band shows as a word and an icon as well as a colour, so it reads without telling the
/// colours apart. The colour and icon follow the band's tone, because "high" is good for
/// potassium and not for pH.
struct SoilMeasurementRow: View {
    let row: SoilMeasurements.Row

    var body: some View {
        if let education = row.education {
            VStack(alignment: .leading, spacing: 6) {
                summary
                if let meaning = education.meaning {
                    Text(meaning)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if let type = row.fertilizerType {
            VStack(alignment: .leading, spacing: 6) {
                summary
                if let effect = type.effect {
                    Text(effect)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                    .multilineTextAlignment(.trailing)
                if let band = row.band, let note = row.note {
                    Label(band.label, systemImage: note.tone.systemImage)
                        .font(.caption)
                        .foregroundStyle(note.tone.tint)
                }
                if let tone = row.fertilizerType?.tone, let verdict = row.fertilizerType?.verdict {
                    Label(verdict, systemImage: tone.systemImage)
                        .font(.caption)
                        .foregroundStyle(tone.tint)
                }
                if let context = row.context {
                    Text(context)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
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
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension SoilTone {
    var systemImage: String {
        switch self {
        case .good: return "checkmark.circle.fill"
        case .watch: return "eye.fill"
        case .act: return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .good: return .green
        case .watch: return .orange
        case .act: return .red
        }
    }
}

#Preview {
    List {
        ForEach(
            SoilMeasurements(
                nitrogen: 170, potassium: 200, ph: 5.6, phMethod: .fieldProbe, phFieldWater: .drained,
                fertilizerType: .organic, fertilizerProduct: "Compost"
            ).rows
        ) { SoilMeasurementRow(row: $0) }
    }
}
