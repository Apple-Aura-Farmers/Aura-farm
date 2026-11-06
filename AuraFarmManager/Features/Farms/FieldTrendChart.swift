import Charts
import SwiftData
import SwiftUI

/// Organisms counted in each of a farm's fields, test by test, so a field whose soil life is
/// falling stands out.
struct FieldTrendChart: View {
    let fields: [Field]

    private struct Point: Identifiable {
        var id: PersistentIdentifier
        var field: String
        var recordedAt: Date
        var total: Int
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Organisms Counted Over Time")
                .font(.headline)
            if points.count < 2 {
                Text("The trend appears once two or more soil tests are filed under this farm's fields.")
                    .foregroundStyle(.secondary)
            } else {
                Chart(points) { point in
                    LineMark(
                        x: .value("Recorded", point.recordedAt),
                        y: .value("Organisms", point.total)
                    )
                    .foregroundStyle(by: .value("Field", point.field))
                    PointMark(
                        x: .value("Recorded", point.recordedAt),
                        y: .value("Organisms", point.total)
                    )
                    .foregroundStyle(by: .value("Field", point.field))
                }
                .frame(height: 200)
                Text("Raw counts. Compare only tests prepared the same way.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Oldest first, so each field's line runs left to right.
    private var points: [Point] {
        fields
            .flatMap { field in
                field.soilTests.map { test in
                    Point(id: test.id, field: field.name, recordedAt: test.recordedAt, total: test.totalCount)
                }
            }
            .sorted { $0.recordedAt < $1.recordedAt }
    }
}
