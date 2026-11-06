import Charts
import SwiftUI

/// One bar per organism group, most counted at the top.
struct OrganismCountChart: View {
    /// Already in the order to draw them.
    let counts: [OrganismCount]

    var body: some View {
        Chart(counts) { organism in
            BarMark(
                x: .value("Count", organism.count),
                y: .value("Organism", organism.commonName)
            )
            .annotation(position: .trailing) {
                Text(organism.count, format: .number)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .chartXAxis(.hidden)
        .frame(height: CGFloat(counts.count) * 30 + 10)
    }
}
