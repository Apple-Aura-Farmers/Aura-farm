import SwiftUI

/// What the guide overlay draws, published by the lab on every analyzed frame (about 10 a
/// second). A value of its own, so only the overlay redraws that often. Main queue only.
@Observable
final class GuideOverlayState {
    var model: GuideOverlayModel?
    private(set) var captureCount = 0
    /// The edge buttons: "✓ Edge" / "✗ Not an edge" while an attached line is at the cross and
    /// the helper is asked, and "Mark edge here" while an edge is looked for.
    private(set) var asksEdge = false
    private(set) var canMarkEdge = false

    func update(
        model: GuideOverlayModel?, captureCount: Int, asksEdge: Bool = false,
        canMarkEdge: Bool = false
    ) {
        if self.model != model { self.model = model }
        if self.captureCount != captureCount { self.captureCount = captureCount }
        if self.asksEdge != asksEdge { self.asksEdge = asksEdge }
        if self.canMarkEdge != canMarkEdge { self.canMarkEdge = canMarkEdge }
    }
}

/// Reads the state and draws it.
struct LiveGuideOverlay: View {
    var state: GuideOverlayState
    /// Only the cross, the target and the rings: the guided scan page words things itself.
    var plain = false
    var body: some View {
        GuideOverlayView(model: state.model, captureCount: state.captureCount, plain: plain)
    }
}

/// The guide drawn over the live preview, Night-mode style: a fixed cross in the centre, a
/// target cross on the picture that the helper brings into it, an arrow pinned inside the
/// edge of the field when the target is out of view, a ring that fills while holding still,
/// and one line of words that only refers to what is drawn. Drawn from values, so a preview
/// can show every state.
struct GuideOverlayView: View {
    var model: GuideOverlayModel?
    var captureCount = 0
    /// Draws no words, count or finished banner (see `LiveGuideOverlay.plain`).
    var plain = false

    @State private var flash = false

    var body: some View {
        ZStack {
            if let model {
                centre(model)
                mark(model)
                if let progress = model.holdProgress { holdRing(model, progress) }
                if let progress = model.checkProgress { checkRing(model, progress) }
                if plain {
                    EmptyView()
                } else if model.isFinished {
                    finished
                } else {
                    if !model.line.isEmpty { line(model.line) }
                    if model.easeOff { easeOff }
                }
                if captureCount > 0, !plain { count }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .onChange(of: (model?.justCaptured ?? false) || (model?.justReachedEdge ?? false)) {
            _, captured in
            guard captured else { return }
            flash = true
            withAnimation(.easeOut(duration: 0.25)) { flash = false }
        }
    }

    // MARK: Pieces

    /// The fixed cross and the zone around it where a target counts as reached.
    private func centre(_ model: GuideOverlayModel) -> some View {
        ZStack {
            Circle().fill(.white.opacity(flash ? 0.6 : 0))
            Circle().stroke(.white.opacity(0.8), lineWidth: 1)
            TargetCross()
                .stroke(.white, lineWidth: 2)
                .frame(width: 28, height: 28)
        }
        .frame(width: model.toleranceRadius * 2, height: model.toleranceRadius * 2)
        .shadow(color: .black.opacity(0.5), radius: 1)
        .position(model.centre)
    }

    @ViewBuilder
    private func mark(_ model: GuideOverlayModel) -> some View {
        switch model.mark {
        case .cross(let point, let tone):
            TargetCross()
                .stroke(Self.colour(tone), lineWidth: 3)
                .background(TargetCross().stroke(.black.opacity(0.7), lineWidth: 6))
                .frame(width: 22, height: 22)
                .position(point)
                .animation(.linear(duration: 0.1), value: point)
        case .pinnedArrow(let point, let angle, let tone, let distance):
            VStack(spacing: 2) {
                ArrowShape()
                    .fill(Self.colour(tone))
                    .overlay(ArrowShape().stroke(.black.opacity(0.7), lineWidth: 1.5))
                    .frame(width: 44, height: 28)
                    .rotationEffect(.radians(angle))
                if let distance {
                    Text("\(distance, specifier: "%.1f") fields")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .background(.black.opacity(0.6), in: Capsule())
                }
            }
            .position(point)
            .animation(.linear(duration: 0.1), value: point)
        case .none:
            EmptyView()
        }
    }

    private func holdRing(_ model: GuideOverlayModel, _ progress: Double) -> some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(.green, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .frame(
                width: model.toleranceRadius * 2 + 12, height: model.toleranceRadius * 2 + 12
            )
            .position(model.centre)
    }

    /// The progress of checking an edge: white, outside the hold ring's place.
    private func checkRing(_ model: GuideOverlayModel, _ progress: Double) -> some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .frame(
                width: model.toleranceRadius * 2 + 12, height: model.toleranceRadius * 2 + 12
            )
            .position(model.centre)
    }

    private func line(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.black.opacity(0.7), in: Capsule())
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
    }

    /// Brief touch: near the cross, faster than a touch counts.
    private var easeOff: some View {
        VStack {
            Spacer()
            Text("Ease off at the cross")
                .font(.headline)
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.orange, in: Capsule())
                .padding(.bottom, 64)
        }
    }

    private var count: some View {
        VStack {
            Text("✓ \(captureCount)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.black.opacity(0.6), in: Capsule())
                .padding(.top, 8)
            Spacer()
        }
    }

    private var finished: some View {
        VStack(spacing: 4) {
            Text("Sample finished ✓").font(.largeTitle.bold())
            Text("\(captureCount) captured").font(.title3)
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
    }

    static func colour(_ tone: GuideTone) -> Color {
        switch tone {
        case .move: .yellow
        case .onTarget: .green
        case .wrongWay, .warning: .orange
        }
    }
}

/// A plus sign filling its frame.
struct TargetCross: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

/// An arrow pointing right, filling its frame.
struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let shaft = rect.height * 0.35
        let head = rect.width * 0.45
        path.move(to: CGPoint(x: rect.minX, y: rect.midY - shaft / 2))
        path.addLine(to: CGPoint(x: rect.maxX - head, y: rect.midY - shaft / 2))
        path.addLine(to: CGPoint(x: rect.maxX - head, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - head, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - head, y: rect.midY + shaft / 2))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY + shaft / 2))
        path.closeSubpath()
        return path
    }
}

#if DEBUG
    // MARK: - Previews

    private struct GuidePreviewBackdrop: View {
        var model: GuideOverlayModel
        var captures = 12

        var body: some View {
            ZStack {
                LinearGradient(
                    colors: [.brown, .gray], startPoint: .topLeading, endPoint: .bottomTrailing)
                GuideOverlayView(model: model, captureCount: captures)
            }
            .frame(width: 390, height: 440)
        }
    }

    private let previewCentre = CGPoint(x: 195, y: 210)

    /// The edge buttons with fixed values, for the previews.
    private struct LiveEdgeFeedbackPreview: View {
        var asks: Bool
        var body: some View { EdgeFeedbackBar(asks: asks, canMark: true) }
    }

    private func previewModel(
        _ mark: GuideMark, progress: Double? = nil, line: String, finished: Bool = false,
        captured: Bool = false, easeOff: Bool = false
    ) -> GuideOverlayModel {
        var model = GuideOverlayModel(
            centre: previewCentre, toleranceRadius: 26, mark: mark, holdProgress: progress,
            justCaptured: captured, line: line, isFinished: finished)
        model.easeOff = easeOff
        return model
    }

    #Preview("Cross moving") {
        GuidePreviewBackdrop(
            model: previewModel(
                .cross(at: CGPoint(x: 255, y: 160), tone: .move), line: "Bring the cross to the centre"))
    }

    #Preview("On target, holding 60%") {
        GuidePreviewBackdrop(
            model: previewModel(
                .cross(at: previewCentre, tone: .onTarget), progress: 0.6, line: "Hold still"))
    }

    #Preview("Arrow far away") {
        GuidePreviewBackdrop(
            model: previewModel(
                .pinnedArrow(
                    at: CGPoint(x: 195, y: 340), angle: .pi / 2, tone: .move, distanceFields: 2.4),
                line: "Bring the cross to the centre"))
    }

    #Preview("Wrong way") {
        GuidePreviewBackdrop(
            model: previewModel(
                .cross(at: CGPoint(x: 140, y: 250), tone: .wrongWay),
                line: "Turn back toward the cross"))
    }

    #Preview("Travel arrow") {
        GuidePreviewBackdrop(
            model: previewModel(
                .pinnedArrow(at: CGPoint(x: 75, y: 210), angle: .pi, tone: .move, distanceFields: nil),
                line: "Follow the arrow until the sample ends"))
    }

    #Preview("Brief touch: touching the cross") {
        GuidePreviewBackdrop(
            model: previewModel(
                .cross(at: CGPoint(x: 205, y: 222), tone: .move), line: "Bring the cross to the centre"))
    }

    #Preview("Brief touch: ticked") {
        GuidePreviewBackdrop(
            model: previewModel(
                .cross(at: CGPoint(x: 195, y: 100), tone: .move), line: "Captured", captured: true))
    }

    #Preview("Brief touch: missed spot") {
        GuidePreviewBackdrop(
            model: previewModel(
                .cross(at: CGPoint(x: 195, y: 290), tone: .wrongWay),
                line: "Missed a spot. Come back a little, slower"))
    }

    #Preview("Brief touch: ease off at the cross, with the speed bar") {
        ZStack(alignment: .bottomLeading) {
            GuidePreviewBackdrop(
                model: previewModel(
                    .cross(at: CGPoint(x: 195, y: 250), tone: .move),
                    line: "Bring the cross to the centre", easeOff: true))
            SpeedMeter(
                speedFraction: 0.14, touchMarker: BriefTouchThresholds().maxTouchSpeedFraction
            )
            .frame(width: 140)
            .padding(8)
        }
        .frame(width: 390, height: 440)
    }

    #Preview("Edge should be here. Confirm?") {
        ZStack {
            GuidePreviewBackdrop(
                model: previewModel(
                    .cross(at: CGPoint(x: 195, y: 330), tone: .move),
                    line: GuideInstruction.expectedEdge.helperText))
            LiveEdgeFeedbackPreview(asks: true)
        }
        .frame(width: 390, height: 440)
    }

    #Preview("A little further, to the line") {
        GuidePreviewBackdrop(
            model: previewModel(
                .pinnedArrow(
                    at: CGPoint(x: 195, y: 350), angle: .pi / 2, tone: .move, distanceFields: nil),
                line: GuideInstruction.lineLead(direction: CGPoint(x: 0, y: 1), nudge: false).helperText))
    }

    #Preview("Last column") {
        GuidePreviewBackdrop(
            model: previewModel(
                .cross(at: CGPoint(x: 195, y: 140), tone: .move),
                line: "Last column. Bring the cross to the centre"))
    }

    #Preview("Finished") {
        GuidePreviewBackdrop(
            model: previewModel(.none, line: "Sample finished", finished: true), captures: 56)
    }
#endif
