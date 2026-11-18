import SwiftUI

/// A generic drawing of the stage's two knobs, one above the other (top = Y, bottom = X), with the
/// one to turn highlighted and an up or down arrow on it: up is away from you, down is towards you. Not a picture
/// of any one microscope: the words say what to do, the drawing says where.
struct KnobDrawingView: View {
    /// What to turn; nil draws both knobs quiet.
    var words: KnobRule.Words?

    var body: some View {
        VStack(spacing: 6) {
            knob(.top)
            knob(.bottom)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(words?.text ?? "Stage knobs")
    }

    private func knob(_ knob: KnobRule.Knob) -> some View {
        let isMain = words?.knob == knob
        // The other knob only takes a little: drawn lightly.
        let isAlso = words.map { $0.alsoOtherKnob && $0.knob != knob } ?? false
        let isLit = isMain || isAlso
        return ZStack {
            Circle()
                .fill(isMain ? Color.accentColor : .gray.opacity(isAlso ? 0.55 : 0.3))
                .frame(width: 36, height: 36)
            // A tick, so a turning knob has something to turn.
            Capsule().fill(.white.opacity(isLit ? 0.95 : 0.5)).frame(width: 4, height: 11)
                .offset(y: -9)
            if isMain, let words {
                // Up is away from you, down is towards you.
                Image(systemName: words.way == .towardsYou ? "arrow.down" : "arrow.up")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 56, height: 52)
    }
}

#Preview("Bottom knob towards you") {
    KnobDrawingView(words: .init(knob: .bottom, way: .towardsYou, alsoOtherKnob: false))
        .padding()
        .background(.black)
}

#Preview("Top knob away from you") {
    KnobDrawingView(words: .init(knob: .top, way: .awayFromYou, alsoOtherKnob: false))
        .padding()
        .background(.black)
}
