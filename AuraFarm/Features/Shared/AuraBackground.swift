import SwiftUI

extension View {
    /// The screen with a warm glow at the top that every Field Helper page and the role
    /// picker share: dark brown in dark mode, cream in light mode. It clears the list or form
    /// background so the screen shows through.
    func auraBackground() -> some View {
        modifier(AuraBackground())
    }
}

extension Color {
    /// The screens' background: dark brown, or the design's cream (#F8F7EA) in light mode.
    static let auraBase = Color(
        light: Color(red: 0xF8 / 255, green: 0xF7 / 255, blue: 0xEA / 255),
        dark: Color(red: 0x1B / 255, green: 0x13 / 255, blue: 0x11 / 255))
    /// The fill of list rows and fields: the design's tertiary fill, which reads brownish over
    /// the screen rather than the system's flat grey.
    /// In light mode it is the design's tan card (#F2E8CC at 80%).
    static let auraRow = Color(
        light: Color(red: 0xF2 / 255, green: 0xE8 / 255, blue: 0xCC / 255).opacity(0.8),
        dark: Color(red: 118 / 255, green: 118 / 255, blue: 128 / 255).opacity(0.24))
}

private struct AuraBackground: ViewModifier {
    private let base = Color.auraBase
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(alignment: .topLeading) { glow }
            .background(base.ignoresSafeArea())
    }

    /// The warm glow at the top of the screen, as two blurred shapes from the design's BG layer.
    /// Redrawn here because the exported SVG relies on blur filters that SwiftUI does not render.
    private var glow: some View {
        ZStack {
            GlowShape(points: [
                (253.734, 432.486), (151.519, 421.36), (94.9, 299.728), (94.9, 121.452), (570.9, 94.9),
                (551.86, 227.659), (355.948, 443.613),
            ])
            .fill(Color.auraBrown)
            .blur(radius: 47.45)
            GlowShape(points: [
                (225.4, 280.072), (123.4, 265.841), (108.9, 196.785), (95.4, 128.862), (570.4, 94.9),
                (525.9, 159.589), (327.4, 294.304),
            ])
            .fill(Color(red: 0xED / 255, green: 0x9C / 255, blue: 0x27 / 255))
            .blur(radius: 47.45)
        }
        .frame(width: 665.8, height: 527.8)
        .opacity(scheme == .dark ? 0.14 : 0.35)
        .offset(x: -118, y: -128)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A closed shape of one starting point, two cubic curves and a line, in the order the design
/// exports them: start, c1, c2, end of curve one, line to, then c1, c2, end of curve two.
private struct GlowShape: Shape {
    var points: [(CGFloat, CGFloat)]

    func path(in rect: CGRect) -> Path {
        let p = points.map { CGPoint(x: $0.0, y: $0.1) }
        var path = Path()
        path.move(to: p[0])
        path.addCurve(to: p[3], control1: p[1], control2: p[2])
        path.addLine(to: p[4])
        path.addCurve(to: p[0], control1: p[5], control2: p[6])
        path.closeSubpath()
        return path
    }
}
