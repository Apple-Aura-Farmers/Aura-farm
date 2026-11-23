import AVFoundation
import SwiftUI

/// Turns frame pixels into points on what is shown. The live preview does it through its
/// layer (`FramePreviewConverter`); a preview with no camera does it by scaling.
protocol FrameToView {
    func viewPoint(of point: CGPoint) -> CGPoint
    func viewRect(of rect: CGRect) -> CGRect
}

extension FramePreviewConverter: FrameToView {}

/// "1 Align · 2 Field · 3 Focus · 4 Stage", the current step highlighted and finished ones
/// ticked.
struct SetupStepIndicator: View {
    var step: LabSetupStep

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(["Align", "Field", "Focus", "Stage"].enumerated()), id: \.offset) {
                index, name in
                if index > 0 { Text("·").foregroundStyle(.white.opacity(0.6)) }
                let finished = step.order > index
                let current = step.order == index
                Text("\(index + 1) \(name)\(finished ? " ✓" : "")")
                    .fontWeight(current ? .bold : .regular)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(current ? Color.accentColor : .clear, in: Capsule())
                    .foregroundStyle(finished ? .green : .white)
            }
        }
        .font(.caption)
        .padding(6)
        .background(.black.opacity(0.65), in: Capsule())
    }
}

/// One line of words on a dark capsule.
struct SetupLine: View {
    var text: String
    var tone = Color.white

    var body: some View {
        Text(text)
            .font(.subheadline.bold())
            .multilineTextAlignment(.center)
            .foregroundStyle(tone)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 8)
    }
}

// MARK: - Align

/// Step 1, drawn from values: the fitted circle (green when every check passes, orange
/// otherwise), a thick red bar along each frame edge that cuts the circle off, the darkest
/// sector shaded blue and the glare sector red, the score, and the worst problem in words.
struct AlignOverlay: View {
    var info: LabSetupInfo
    var mapper: (any FrameToView)?

    /// Shown while setup is back at align because alignment was lost.
    static let lostText = "Alignment lost. Fix it and setup carries on"

    static func text(for info: LabSetupInfo) -> (text: String, isGood: Bool) {
        if info.isAlignmentPassed { return ("Phone aligned ✓", true) }
        if info.resumeStep != nil { return (lostText, false) }
        switch info.alignment.problems.first {
        case .noCircle?:
            return (
                "Can't see the microscope's circle. Check the phone is over the eyepiece and the light is on",
                false
            )
        case .clipped?:
            return (
                "The circle is cut off at the red edge. Move the phone until the whole circle shows",
                false
            )
        case .notRound?:
            return ("The circle is misshapen. Centre the phone over the eyepiece", false)
        case .uneven?:
            return (
                "One side is darker (blue). Nudge or tilt the phone until it evens out", false
            )
        case .glare?:
            return ("Glare (red). Tilt the phone slightly, or shade the eyepiece", false)
        case nil:
            return ("Looks good. Hold the phone steady", true)
        }
    }

    private var trendMark: String {
        switch info.trend {
        case .better: "▲"
        case .worse: "▼"
        case .steady: "–"
        }
    }

    var body: some View {
        let words = Self.text(for: info)
        ZStack {
            Canvas { context, size in draw(&context, size) }
                .allowsHitTesting(false)
            VStack(spacing: 8) {
                SetupStepIndicator(step: .align)
                Spacer()
                Text("Alignment \(Int(info.alignment.score.rounded())) \(trendMark)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.7), in: Capsule())
                SetupLine(text: words.text, tone: words.isGood ? .green : .white)
            }
            .padding(8)
        }
    }

    private func draw(_ context: inout GraphicsContext, _ size: CGSize) {
        guard let mapper else { return }
        let reading = info.alignment
        if let circle = reading.circle, reading.found {
            // Wedges first, so the outline stays on top.
            if reading.problems.contains(.uneven), let sector = reading.darkestSector {
                context.fill(
                    wedge(sector, of: circle, mapper), with: .color(.blue.opacity(0.4)))
            }
            if reading.problems.contains(.glare), let sector = reading.brightestSector {
                context.fill(
                    wedge(sector, of: circle, mapper), with: .color(.red.opacity(0.4)))
            }
            let box = mapper.viewRect(
                of: CGRect(
                    x: circle.centre.x - circle.radius, y: circle.centre.y - circle.radius,
                    width: circle.radius * 2, height: circle.radius * 2))
            context.stroke(
                Path(ellipseIn: box), with: .color(reading.passes ? .green : .orange),
                lineWidth: 3)
        }
        for side in reading.clippedSides {
            context.fill(bar(for: side, mapper, size), with: .color(.red))
        }
    }

    /// A pie slice of sector `index`: sector 0 is centred on frame +x, and they go clockwise
    /// in top-down frame coordinates, so it is drawn in frame pixels and mapped point by
    /// point, which keeps it on the right part of the picture however it is rotated.
    private func wedge(_ index: Int, of circle: FieldCircle, _ mapper: any FrameToView) -> Path {
        let count = Double(AlignmentThresholds().sectorCount)
        let slice = 2 * Double.pi / count
        let from = Double(index) * slice - slice / 2
        var path = Path()
        path.move(to: mapper.viewPoint(of: circle.centre))
        for step in 0...12 {
            let angle = from + slice * Double(step) / 12
            path.addLine(
                to: mapper.viewPoint(
                    of: CGPoint(
                        x: Double(circle.centre.x) + circle.radius * cos(angle),
                        y: Double(circle.centre.y) + circle.radius * sin(angle))))
        }
        path.closeSubpath()
        return path
    }

    /// A thick bar along the edge of the view where that frame side shows: found from where
    /// the middle of the side lands relative to the middle of the frame.
    private func bar(for side: FrameSide, _ mapper: any FrameToView, _ size: CGSize) -> Path {
        let frame = info.frameSize
        let middle = mapper.viewPoint(of: CGPoint(x: frame.width / 2, y: frame.height / 2))
        let edge: CGPoint
        switch side {
        case .top: edge = CGPoint(x: frame.width / 2, y: 0)
        case .bottom: edge = CGPoint(x: frame.width / 2, y: frame.height)
        case .left: edge = CGPoint(x: 0, y: frame.height / 2)
        case .right: edge = CGPoint(x: frame.width, y: frame.height / 2)
        }
        let point = mapper.viewPoint(of: edge)
        let thickness = 8.0
        if abs(point.x - middle.x) >= abs(point.y - middle.y) {
            let x = min(max(point.x, thickness / 2), size.width - thickness / 2)
            return Path(CGRect(x: x - thickness / 2, y: 0, width: thickness, height: size.height))
        }
        let y = min(max(point.y, thickness / 2), size.height - thickness / 2)
        return Path(CGRect(x: 0, y: y - thickness / 2, width: size.width, height: thickness))
    }
}

// MARK: - Focus

/// Step 2, drawn from values: the thin outline of the square the sharpness is measured in,
/// a horizontal meter with the current sharpness and a white tick at the peak, and one line
/// of words.
struct FocusOverlay: View {
    /// The lab's own step chip; the guided scan page has its own indicator.
    var showsIndicator = true
    var info: LabSetupInfo
    var reading: FocusReading?
    /// The two-sided dial, once the peak has been passed: it replaces the one-sided meter.
    var dial: FocusDialReading?
    var mapper: (any FrameToView)?

    static func text(for state: FocusGuideState?) -> String {
        switch state {
        case nil, .turnOneWay?: "Turn the focus knob slowly in one direction"
        case .passedPeak?: "Past the sharpest point. Turn back slowly"
        case .nearPeak?: "Almost there. Turn very slowly, then stop"
        case .focused?: "Best focus found ✓"
        case .needsSample?: "Not enough detail. Move to an area with sample, then focus"
        }
    }

    private func tone(_ state: FocusGuideState?) -> Color {
        switch state {
        case .focused?: .green
        case .nearPeak?: .yellow
        case .passedPeak?: .orange
        case .needsSample?: .red
        default: .white
        }
    }

    var body: some View {
        ZStack {
            Canvas { context, _ in
                guard let mapper, let square = info.focusSquare else { return }
                context.stroke(
                    Path(mapper.viewRect(of: square)), with: .color(.white.opacity(0.8)),
                    lineWidth: 1)
            }
            .allowsHitTesting(false)
            VStack(spacing: 8) {
                if showsIndicator { SetupStepIndicator(step: .focus) }
                Spacer()
                if let dial {
                    FocusDialView(reading: dial)
                    SetupLine(text: dial.message, tone: dial.isGreen ? .green : .orange)
                } else {
                    FocusMeter(reading: reading, tone: tone(reading?.state))
                    SetupLine(text: Self.text(for: reading?.state), tone: tone(reading?.state))
                }
            }
            .padding(8)
        }
    }
}

/// The current sharpness as a bar, the highest seen as a white tick. The scale runs a
/// little past the peak so the tick is never at the very end.
struct FocusMeter: View {
    var reading: FocusReading?
    var tone: Color

    var body: some View {
        GeometryReader { proxy in
            let scale = max((reading?.peak ?? 0) * 1.15, 1)
            let current = min((reading?.current ?? 0) / scale, 1)
            let peak = min((reading?.peak ?? 0) / scale, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.65))
                Capsule().fill(tone).frame(width: max(proxy.size.width * current, 6))
                Rectangle().fill(.white).frame(width: 3)
                    .offset(x: proxy.size.width * peak - 1.5)
                    .opacity(reading == nil ? 0 : 1)
            }
        }
        .frame(height: 14)
        .padding(.horizontal, 24)
    }
}

// MARK: - Stage

/// Step 4: the progress of the two knob runs and the words for each state, with a Skip button
/// that keeps the picture as it is.
struct StageOverlay: View {
    var showsIndicator = true
    var progress: StageAxesProgress?
    /// The automated stage measures the tilt: no knob instructions, no Skip.
    var automated = false
    var onSkip: () -> Void = {}

    private var isDone: Bool { progress?.step == .done }

    private var tone: Color {
        guard let progress else { return .white }
        if case .failed = progress.step { return .red }
        if progress.isPause { return .green }
        if progress.isHeld || progress.nothingToFollow {
            return .orange
        }
        return isDone ? .green : .white
    }

    var body: some View {
        VStack(spacing: 8) {
            if showsIndicator { SetupStepIndicator(step: .stage) }
            Spacer()
            if automated {
                SetupLine(text: "The automated stage measures the tilt: no knob turning needed", tone: .white)
            } else {
                ProgressView(
                    value: min(
                        (progress?.travelFields ?? 0) / StageAxesThresholds().minTravelFields, 1)
                )
                .tint(tone)
                .opacity(progress?.nothingToFollow == true ? 0.3 : 1)
                .padding(.horizontal, 24)
                Text(String(format: "%.1f fields", progress?.travelFields ?? 0))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
                SetupLine(text: progress?.message ?? StageAxesCalibration.waitXMessage, tone: tone)
                if let hint = progress?.hint { SetupLine(text: hint, tone: .white) }
                Button("Skip", action: onSkip)
                    .buttonStyle(.borderedProminent)
                    .tint(.gray)
                    .font(.caption)
            }
        }
        .padding(8)
    }
}

// MARK: - Edge line

/// The edge-line detector's candidate as a thin cyan polyline in the box. Drawing only: no
/// guide decision uses it.
struct EdgeLineOverlay: View {
    var state: EdgeLineState
    var mapper: (any FrameToView)?
    @AppStorage("slideLab.showEdgeLine") private var shows = true

    /// Cyan for a candidate, green once it has been seen moving with the slide, and the
    /// word "edge" beside it when the guide has confirmed it.
    static func colour(for lineState: String) -> Color {
        lineState == "attached" || lineState == "confirmed" ? .green : .cyan
    }

    var body: some View {
        Canvas { context, _ in
            guard shows, let mapper, state.path.count > 1 else { return }
            let points = state.path.map { mapper.viewPoint(of: $0) }
            var line = Path()
            line.move(to: points[0])
            for point in points.dropFirst() { line.addLine(to: point) }
            let colour = Self.colour(for: state.lineState)
            context.stroke(line, with: .color(colour), lineWidth: 1.5)
            if state.lineState == "confirmed" {
                let middle = points[points.count / 2]
                context.draw(
                    Text("edge").font(.caption.bold()).foregroundStyle(colour),
                    at: CGPoint(x: middle.x + 20, y: middle.y - 10))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Run monitor

/// While the run is paused: the words for the reason, and (for alignment) the confirmed circle
/// outlined in orange so the phone can be lined up with it again.
struct PausedOverlay: View {
    var monitor: RunMonitorInfo
    var mapper: (any FrameToView)?
    /// "Resume anyway", shown while paused for focus.
    var onResumeAnyway: (() -> Void)?
    /// "In focus – empty area", shown under "Resume anyway" while paused for focus; nil hides it.
    var onEmptyArea: (() -> Void)?

    var body: some View {
        if let reason = monitor.state.pauseReason {
            ZStack {
                Canvas { context, _ in
                    guard reason == .alignment, let mapper, let circle = monitor.circle else { return }
                    let box = mapper.viewRect(
                        of: CGRect(
                            x: circle.centre.x - circle.radius,
                            y: circle.centre.y - circle.radius, width: circle.radius * 2,
                            height: circle.radius * 2))
                    context.stroke(Path(ellipseIn: box), with: .color(.orange), lineWidth: 4)
                }
                .allowsHitTesting(false)
                VStack {
                    Text("Paused")
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(.orange, in: Capsule())
                        .foregroundStyle(.black)
                    if reason == .focus, let dial = monitor.dial {
                        FocusDialView(reading: dial)
                        SetupLine(text: dial.message, tone: dial.isGreen ? .green : .orange)
                        if let hint = monitor.focusHint {
                            SetupLine(text: hint, tone: .white)
                        }
                    } else if !GuideInstruction.paused(reason).helperText.isEmpty {
                        SetupLine(text: GuideInstruction.paused(reason).helperText, tone: .orange)
                    }
                    if reason == .focus, let onResumeAnyway {
                        Button("Resume anyway", action: onResumeAnyway)
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .foregroundStyle(.black)
                    }
                    if reason == .focus, let onEmptyArea {
                        Button("In focus – empty area", action: onEmptyArea)
                            .buttonStyle(.bordered)
                            .tint(.orange)
                    }
                    Spacer()
                }
                .padding(8)
            }
        }
    }
}

// MARK: - Stage limit

/// The "Stage limit" button, and the hint that offers it after a while on the same move.
struct StageLimitControl: View {
    var showsHint: Bool
    var onTap: () -> Void

    static let hint = "Stage won't go further? Tap Stage limit"

    var body: some View {
        VStack(spacing: 4) {
            if showsHint {
                Text(Self.hint)
                    .font(.footnote.bold())
                    .foregroundStyle(.orange)
            }
            Button("Stage limit", action: onTap)
                .buttonStyle(.bordered)
                .tint(showsHint ? .orange : .gray)
        }
    }
}

// MARK: - Live views

/// Reads the model and draws the setup step: align or focus. Field and done have their
/// own screens.
struct LiveSetupOverlay: View {
    var model: ScanEngine
    var previewLayer: AVCaptureVideoPreviewLayer?
    var showsIndicator = true
    /// The automated stage measures the stage step itself.
    var automatedStage = false
    /// The picture's display transform (centred and zoomed from the focus step on), so the focus
    /// square lands on the picture.
    var display = CGAffineTransform.identity

    var body: some View {
        let info = model.setupInfo
        let mapper = FramePreviewConverter(
            layer: previewLayer, frameSize: info.frameSize, display: display)
        switch info.step {
        case .align: AlignOverlay(info: info, mapper: mapper)
        case .focus:
            FocusOverlay(
                showsIndicator: showsIndicator, info: info, reading: model.focusMeter.reading,
                dial: model.focusMeter.dial, mapper: mapper)
        case .stage:
            StageOverlay(
                showsIndicator: showsIndicator, progress: info.stage, automated: automatedStage,
                onSkip: { model.skipStage() })
        case .field, .done: EmptyView()
        }
    }
}
