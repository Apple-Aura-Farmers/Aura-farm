import SwiftUI

/// The setup step's instruction, in the same card and space as the scan's instruction card, with
/// the align step's ticks inside it. Nothing is drawn over it.
struct SetupCardView: View {
    var sentence: String
    /// An orange line above the sentence ("Alignment lost…").
    var notice: String?
    var ticks: AlignmentTicks?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let notice {
                Text(notice).font(.subheadline.bold()).foregroundStyle(.orange)
            }
            Text(sentence)
                .font(.title3.weight(.bold))
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            if let ticks { AlignmentTicksView(ticks: ticks) }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 20))
        .foregroundStyle(.white)
    }
}

#Preview("Setup card with ticks") {
    var reading = AlignmentReading()
    reading.found = true
    reading.problems = [.uneven]
    return SetupCardView(
        sentence: GuidedScanSetupStage.align.sentence, notice: nil,
        ticks: AlignmentTicks(reading: reading, passed: false)
    )
    .padding().background(.gray)
}
