import SwiftUI

/// How to get from a bag of soil to a slide under the microscope.
///
/// It sits with the sample details because that is where someone stands before a sweep,
/// and a count is only worth as much as the slide it was taken from: the same soil mixed
/// at a different strength gives a different number of organisms per droplet.
struct SamplePrepView: View {
    /// The recipe, kept here as data so the amounts are in one place rather than spread
    /// through the sentences.
    static let gramsOfSoil = 1.0
    static let millilitresOfWater = 10.0
    static let settlingMinutes = 1

    private struct Step: Identifiable {
        var id: Int
        var title: String
        var detail: String?
    }

    private var steps: [Step] {
        [
            Step(
                id: 1,
                title: "Weigh out \(Self.gramsOfSoil.formatted()) g of soil",
                detail: "Put the same amount in every time, or the counts cannot be compared."
            ),
            Step(
                id: 2,
                title: "Add \(Self.millilitresOfWater.formatted()) mL of water",
                detail: nil
            ),
            Step(
                id: 3,
                title: "Mix it with the small spoon",
                detail: nil
            ),
            Step(
                id: 4,
                title: "Let it sit for \(Self.settlingMinutes) minute",
                detail: nil
            ),
            Step(
                id: 5,
                title: "Take one droplet onto the slide",
                detail: nil
            ),
            Step(
                id: 6,
                title: "Hold the cover slip at 45° and drop it",
                detail: "Lowering it at an angle rather than flat keeps air from being "
                    + "trapped underneath, and a bubble looks like nothing else on the slide."
            ),
        ]
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Soil", value: "\(Self.gramsOfSoil.formatted()) g")
                LabeledContent("Water", value: "\(Self.millilitresOfWater.formatted()) mL")
                LabeledContent("Settle", value: "\(Self.settlingMinutes) min")
            } header: {
                Text("The mix")
            } footer: {
                Text("Put these in Amounts on the sample details, so the count has them.")
            }

            Section("Steps") {
                ForEach(steps) { step in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(step.id)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 18, alignment: .trailing)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.title)
                            if let detail = step.detail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "Step \(step.id). \(step.title). \(step.detail ?? "")")
                }
            }

            Section {
                SweepPatternView()
                    .padding(.vertical, 4)
            } header: {
                Text("Walking the slide")
            } footer: {
                Text(
                    "Once it is under the lens, move the slide across, down one step, then "
                        + "back the other way. The app says which way to go next and keeps a "
                        + "frame each time you have moved far enough.")
            }
        }
        .navigationTitle("Preparing a sample")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { SamplePrepView() }
}
