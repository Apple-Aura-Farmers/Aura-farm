import SwiftUI

/// The align step's checks as ticks: whole circle in view, round, evenly lit, no glare. Drawn
/// from `AlignmentTicks`, which the lab's own alignment reading fills in.
struct AlignmentTicksView: View {
    var ticks: AlignmentTicks

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading),
                ],
                alignment: .leading, spacing: 6
            ) {
                ForEach(Array(ticks.lines.enumerated()), id: \.offset) { _, line in
                    Label {
                        Text(line.text).font(.subheadline).lineLimit(2).minimumScaleFactor(0.8)
                    } icon: {
                        Image(systemName: line.isOK ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(line.isOK ? .green : .white.opacity(0.5))
                    }
                }
            }
            if ticks.passed {
                Label("Aligned", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Align ticks") {
    var reading = AlignmentReading()
    reading.found = true
    reading.problems = [.uneven]
    return VStack(spacing: 20) {
        AlignmentTicksView(ticks: AlignmentTicks(reading: reading, passed: false))
        AlignmentTicksView(ticks: AlignmentTicks(reading: AlignmentReading(found: true), passed: true))
    }
    .padding()
    .background(.black)
    .foregroundStyle(.white)
}
