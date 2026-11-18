import SwiftUI

/// A generic drawing of the stage's two knobs, one above the other (top = Y, bottom = X), with the
/// one to turn highlighted and a curved arrow around it for the turning direction. Not a picture
/// of any one microscope: the words say what to do, the drawing says where.
struct KnobDrawingView: View {
    /// What to turn; nil draws both knobs quiet.
    var words: KnobRule.Words?

    var body: some View {
        VStack(spacing: 10) {
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
                .frame(width: 44, height: 44)
            // A tick, so a turning knob has something to turn.
            Capsule().fill(.white.opacity(isLit ? 0.95 : 0.5)).frame(width: 4, height: 14)
                .offset(y: -11)
            if isMain, let words {
                TurnArrow(towardsYou: words.way == .towardsYou)
                    .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 62, height: 62)
            }
        }
        .frame(width: 68, height: 62)
    }
}

/// A three-quarter arc with an arrowhead. Towards you turns one way round, away from you the
/// other; the words always say which, so the drawing may be read either way.
private struct TurnArrow: Shape {
    var towardsYou: Bool

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let start = Angle.degrees(towardsYou ? 200 : -20)
        let end = Angle.degrees(towardsYou ? 340 : 160)
        var path = Path()
        path.addArc(
            center: centre, radius: radius, startAngle: start, endAngle: end,
            clockwise: !towardsYou)
        // Arrowhead at the end of the arc.
        let tip = CGPoint(
            x: centre.x + radius * cos(end.radians), y: centre.y + radius * sin(end.radians))
        let heading = end.radians + (towardsYou ? .pi / 2 : -.pi / 2)
        for side in [-0.5, 0.5] {
            let angle = heading + .pi + side
            path.move(to: tip)
            path.addLine(
                to: CGPoint(x: tip.x + 11 * cos(angle), y: tip.y + 11 * sin(angle)))
        }
        return path
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
