import SwiftUI

/// A field in a farm's list: its name and crop, when it was last tested, and its latest NPK.
struct FieldRow: View {
    let field: Field

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(field.name)
                    .font(.body.weight(.medium))
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(lastTested)
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    /// "Rice · 1.2 ha · 3 soil tests"
    private var details: String {
        var parts = [field.crop]
        if let area = field.areaHectares {
            parts.append("\(area.formatted(.number)) ha")
        }
        let tests = field.soilTests.count
        parts.append(tests == 1 ? "1 soil test" : "\(tests) soil tests")
        if let npk = field.latestNutrientTest {
            parts.append("NPK \(npk.testedAt.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " · ")
    }

    private var lastTested: String {
        guard let latest = field.latestSoilTest else { return "Not tested yet" }
        return "Last tested \(latest.recordedAt.formatted(date: .abbreviated, time: .omitted))"
    }
}
