import SwiftUI

/// One soil test in a list: the sample, when, where it is filed, and how much was counted.
struct SoilTestRow: View {
    let test: SoilTest
    /// Off on a field's own page, where the place goes without saying.
    var showsPlace = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(test.sampleID)
                    .font(.body.weight(.medium))
                Spacer()
                Text("\(test.totalCount) counted")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(test.recordedAt, format: .dateTime.day().month().year().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
            if showsPlace {
                Text(test.placeLabel)
                    .font(.caption)
                    .foregroundStyle(test.field == nil ? Color.orange : Color.secondary)
            }
        }
    }
}
