import SwiftUI

/// The card at the bottom of the guided scan page: the knob drawing (when there is a knob), one
/// line of large words, and Yes / No on the question. Drawn from a `HelperInstruction`, so a
/// preview can show every card.
struct HelperCardView: View {
    var card: HelperInstruction
    var onYes: () -> Void = {}
    var onNo: () -> Void = {}

    var body: some View {
        HStack(spacing: 16) {
            if card.knob != nil {
                KnobDrawingView(words: card.knob)
            } else if let progress = card.progress {
                ring(progress)
            } else if let symbol {
                Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(card.text)
                    .font(.title.weight(.bold))
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)
                if case .question = card { answers }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 20))
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }

    /// A ring that fills while holding still or confirming; empty ring without progress.
    private func ring(_ progress: Double) -> some View {
        ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: 8)
            Circle().trim(from: 0, to: progress)
                .stroke(.green, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "hand.raised.fill").font(.title2)
        }
        .frame(width: 62, height: 62)
    }

    private var answers: some View {
        HStack(spacing: 12) {
            Button(action: onYes) { Label("Yes", systemImage: "checkmark") }
                .buttonStyle(.borderedProminent).tint(.green)
            Button(action: onNo) { Label("No", systemImage: "xmark") }
                .buttonStyle(.borderedProminent).tint(.red)
        }
        .controlSize(.large)
        .font(.title3.bold())
    }

    private var symbol: String? {
        switch card {
        case .refocus: "scope"
        case .phoneMoved: "iphone.gen3.radiowaves.left.and.right"
        case .edgeFound: "checkmark.seal.fill"
        case .lastColumn: "flag.checkered"
        case .finished: "checkmark.circle.fill"
        case .waiting: "hourglass"
        case .question: "questionmark.circle.fill"
        case .stop: "hand.raised.fill"
        case .tooHot: "thermometer.high"
        case .turn, .backALittle, .backToLine: nil
        }
    }

    private var tint: Color {
        switch card {
        case .phoneMoved, .tooHot: .orange
        case .edgeFound, .finished, .lastColumn: .green
        default: .white
        }
    }
}

#Preview("Turn: all four directions") {
    let rule = KnobRule()
    VStack(spacing: 10) {
        // Arrow left, right, up, down on the displayed picture.
        ForEach(0..<4, id: \.self) { index in
            let directions = [(-1.0, 0.0), (1, 0), (0, -1), (0, 1)]
            let direction = CGPoint(x: directions[index].0, y: directions[index].1)
            if let words = rule.words(forArrowDirection: direction) {
                HelperCardView(card: .turn(words))
            }
        }
    }
    .padding()
    .background(.gray)
}

#Preview("Status cards") {
    let words = KnobRule().words(forArrowDirection: CGPoint(x: 1, y: 0))
    ScrollView {
        VStack(spacing: 10) {
            HelperCardView(card: .stop(progress: 0.6, note: nil))
            if let words { HelperCardView(card: .backALittle(words)) }
            HelperCardView(card: .refocus)
            HelperCardView(card: .phoneMoved)
            HelperCardView(card: .edgeFound)
            HelperCardView(card: .lastColumn)
            HelperCardView(card: .finished)
            HelperCardView(card: .waiting("Loading the counting model…"))
            HelperCardView(card: .question)
            HelperCardView(card: .tooHot)
        }
        .padding()
    }
    .background(.gray)
}
