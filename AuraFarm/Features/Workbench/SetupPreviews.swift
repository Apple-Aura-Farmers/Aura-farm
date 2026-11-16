#if DEBUG
    import SwiftUI

    /// The setup screens with fixed values, drawn over a synthetic eyepiece picture. There is no
    /// camera, so frame pixels are mapped to the panel by a plain scale.
    struct SetupPreviewPanel: View {
        enum Scene: CaseIterable {
            case alignClippedRight, alignUneven, alignGlare, alignPassed
            case focusTurnOneWay, focusPassedPeak, focusFocused, focusNeedsSample
            case stageWaitX, stageWaitY, stageRejected, stageDone, stageStart, stageNothingToFollow
            case pausedAlignment, pausedFocus

            var title: String {
                switch self {
                case .alignClippedRight: "Align: clipped right"
                case .alignUneven: "Align: uneven (blue)"
                case .alignGlare: "Align: glare (red)"
                case .alignPassed: "Align: passed"
                case .focusTurnOneWay: "Focus: turnOneWay"
                case .focusPassedPeak: "Focus: passedPeak"
                case .focusFocused: "Focus: focused"
                case .focusNeedsSample: "Focus: needsSample"
                case .stageWaitX: "Stage: waitX, 1.2 of 2 fields"
                case .stageWaitY: "Stage: waitY, 0.4 of 2 fields"
                case .stageRejected: "Stage: rejected (both knobs)"
                case .stageDone: "Stage: done, tilt 9.6°"
                case .stageStart: "Stage: start (particles hint)"
                case .stageNothingToFollow: "Stage: nothing to follow (dim bar)"
                case .pausedAlignment: "Paused: alignment (orange outline)"
                case .pausedFocus: "Paused: focus"
                }
            }
        }

        static let frameSize = CGSize(width: 1280, height: 720)
        static let panel = CGSize(width: 400, height: 260)
        private static let scale = 400.0 / 1280.0
        private static var offset: CGPoint { CGPoint(x: 0, y: (panel.height - 225) / 2) }

        /// Frame pixels to panel points.
        struct Mapper: FrameToView {
            func viewPoint(of point: CGPoint) -> CGPoint {
                CGPoint(
                    x: point.x * SetupPreviewPanel.scale + SetupPreviewPanel.offset.x,
                    y: point.y * SetupPreviewPanel.scale + SetupPreviewPanel.offset.y)
            }

            func viewRect(of rect: CGRect) -> CGRect {
                let scale = SetupPreviewPanel.scale
                return CGRect(
                    origin: viewPoint(of: rect.origin),
                    size: CGSize(width: rect.width * scale, height: rect.height * scale))
            }
        }

        var scene: Scene

        /// The values each scene shows.
        static func info(for scene: Scene) -> (info: LabSetupInfo, meter: FocusReading?) {
            var info = LabSetupInfo(step: .align, frameSize: frameSize)
            let centred = FieldCircle(centre: CGPoint(x: 640, y: 360), radius: 300)
            var reading = AlignmentReading()
            reading.found = true
            reading.circle = centred
            reading.roundness = 0.96
            reading.evenness = 0.95
            reading.glareRatio = 1.05
            reading.saturatedShare = 0
            reading.sectorMeans = [Double](repeating: 200, count: 8)
            reading.darkestSector = 3
            reading.brightestSector = 5
            reading.score = 90
            switch scene {
            case .alignClippedRight:
                reading.circle = FieldCircle(centre: CGPoint(x: 1010, y: 360), radius: 300)
                reading.clippedSides = [.right]
                reading.roundness = 0.8
                reading.problems = [.clipped]
                reading.score = 38
                info.trend = .worse
            case .alignUneven:
                reading.evenness = 0.62
                reading.darkestSector = 0
                reading.brightestSector = 4
                reading.problems = [.uneven]
                reading.score = 55
                info.trend = .better
            case .alignGlare:
                reading.glareRatio = 1.5
                reading.saturatedShare = 0.04
                reading.brightestSector = 7
                reading.problems = [.glare]
                reading.score = 60
            case .alignPassed:
                info.isAlignmentPassed = true
                reading.score = 92
                info.trend = .steady
            case .focusTurnOneWay, .focusPassedPeak, .focusFocused, .focusNeedsSample:
                info.step = .focus
                info.focusSquare = FieldCentring.focusSquareForPreview(circle: centred)
            case .stageWaitX:
                info.step = .stage
                info.stage = StageAxesProgress(
                    step: .waitX, travelFields: 1.2, message: StageAxesCalibration.waitXMessage)
            case .stageWaitY:
                info.step = .stage
                info.stage = StageAxesProgress(
                    step: .waitY, travelFields: 0.4, message: StageAxesCalibration.waitYMessage)
            case .stageRejected:
                info.step = .stage
                info.stage = StageAxesProgress(
                    step: .waitX, travelFields: 0, message: StageAxesCalibration.rejectedMessage)
            case .stageDone:
                info.step = .stage
                info.stage = StageAxesProgress(
                    step: .done, travelFields: 2.2, message: "Stage straightened ✓ (tilt 9.6°)")
            case .stageStart:
                info.step = .stage
                info.stage = StageAxesProgress(
                    step: .waitX, travelFields: 0, message: StageAxesCalibration.waitXMessage,
                    hint: StageAxesCalibration.particlesHint)
            case .stageNothingToFollow:
                info.step = .stage
                info.stage = StageAxesProgress(
                    step: .waitY, travelFields: 0.3,
                    message: StageAxesCalibration.nothingToFollowMessage, nothingToFollow: true)
            case .pausedAlignment:
                // The phone moved: the live circle is off to the right of the confirmed one.
                info.step = .done
                reading.circle = FieldCircle(centre: CGPoint(x: 800, y: 380), radius: 300)
                info.monitor = RunMonitorInfo(
                    state: .pausedAlignment, circleShift: 0.55, circleRadiusChange: 0,
                    circle: centred)
            case .pausedFocus:
                info.step = .done
                info.monitor = RunMonitorInfo(
                    state: .pausedFocus, focusIndex: 0.9, focusBaseline: 2.1, circle: centred)
            }
            info.alignment = reading
            let meter: FocusReading?
            switch scene {
            case .focusTurnOneWay:
                meter = FocusReading(state: .turnOneWay, current: 220, peak: 260, level: 0.85)
            case .focusPassedPeak:
                meter = FocusReading(state: .passedPeak, current: 230, peak: 520, level: 0.44)
            case .focusFocused:
                meter = FocusReading(state: .focused, current: 505, peak: 520, level: 0.97)
            case .focusNeedsSample:
                meter = FocusReading(state: .needsSample, current: 70, peak: 90, level: 0.78)
            default: meter = nil
            }
            info.focus = meter
            return (info, meter)
        }

        var body: some View {
            let values = Self.info(for: scene)
            VStack(spacing: 4) {
                ZStack {
                    picture(values.info)
                    switch values.info.step {
                    case .align:
                        AlignOverlay(info: values.info, mapper: Mapper())
                    case .stage:
                        StageOverlay(progress: values.info.stage)
                    case .done:
                        PausedOverlay(monitor: values.info.monitor, mapper: Mapper())
                    default:
                        FocusOverlay(info: values.info, reading: values.meter, mapper: Mapper())
                    }
                }
                .frame(width: Self.panel.width, height: Self.panel.height)
                .clipped()
                .overlay(Rectangle().stroke(.white.opacity(0.5), lineWidth: 1))
                Text(scene.title).font(.caption).foregroundStyle(.white)
            }
        }

        /// The eyepiece picture: a dark frame, a bright disc, and the scene's own flaw.
        private func picture(_ info: LabSetupInfo) -> some View {
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                let mapper = Mapper()
                guard let circle = info.alignment.circle else { return }
                let box = mapper.viewRect(
                    of: CGRect(
                        x: circle.centre.x - circle.radius, y: circle.centre.y - circle.radius,
                        width: circle.radius * 2, height: circle.radius * 2))
                var disc = Path(ellipseIn: box)
                context.clip(to: Path(CGRect(origin: .zero, size: size)))
                context.fill(disc, with: .color(Color(white: 0.8)))
                if info.alignment.problems.contains(.uneven) {
                    context.fill(
                        disc,
                        with: .linearGradient(
                            Gradient(colors: [.clear, .black.opacity(0.55)]),
                            startPoint: CGPoint(x: box.midX, y: box.midY),
                            endPoint: CGPoint(x: box.maxX, y: box.midY)))
                }
                if info.alignment.problems.contains(.glare) {
                    let spot = mapper.viewPoint(
                        of: CGPoint(x: circle.centre.x + 190, y: circle.centre.y - 190))
                    disc = Path(ellipseIn: CGRect(x: spot.x - 18, y: spot.y - 18, width: 36, height: 36))
                    context.fill(disc, with: .color(.white))
                }
            }
        }
    }

    extension FieldCentring {
        /// The focus square for a drawn circle, for the previews.
        static func focusSquareForPreview(circle: FieldCircle) -> CGRect {
            LabSetupSession.focusSquare(
                for: circle, frameSize: SetupPreviewPanel.frameSize)
        }
    }

    /// The guide's Stage limit button with its hint, and the check-edge arrow, over a stand-in
    /// picture.
    struct GuideExtrasPanel: View {
        private static let size = CGSize(width: 400, height: 260)

        /// The overlay the real guide draws for "step back and come forward": an arrow pinned
        /// inside the field's edge, pointing back down the column.
        static var checkEdgeModel: GuideOverlayModel {
            let step = GuideStep(
                instruction: .checkEdge(toward: CGPoint(x: 0, y: 1)), target: nil, capture: nil,
                stateName: "column 1 up", column: 1, isFinished: false)
            return GuideOverlayModel.make(
                step: step, position: .zero, tracking: .paused,
                centre: CGPoint(x: size.width / 2, y: size.height / 2), pointsPerField: 120,
                fieldRadius: 84, alignToleranceFields: 0.15)
        }

        var body: some View {
            HStack(spacing: 12) {
                VStack(spacing: 4) {
                    ZStack {
                        LinearGradient(
                            colors: [.brown, .gray], startPoint: .topLeading,
                            endPoint: .bottomTrailing)
                        GuideOverlayView(model: Self.checkEdgeModel)
                    }
                    .frame(width: Self.size.width, height: Self.size.height)
                    .clipped()
                    Text("checkEdge arrow").font(.caption).foregroundStyle(.white)
                }
                VStack(spacing: 4) {
                    VStack(spacing: 16) {
                        StageLimitControl(showsHint: true, onTap: {})
                        StageLimitControl(showsHint: false, onTap: {})
                    }
                    .frame(width: Self.size.width, height: Self.size.height)
                    .background(Color(white: 0.2))
                    Text("Stage limit button, with and without the hint").font(.caption)
                        .foregroundStyle(.white)
                }
            }
        }
    }

    /// The cyan edge line the detector finds on a synthetic edge (bright to the right, a slight
    /// tilt, dots on both sides), drawn over the box.
    struct EdgeLinePreviewPanel: View {
        private let state: EdgeLineState = {
            let cells = 200
            var luma = [Float](repeating: 100, count: cells * cells)
            for y in 0..<cells {
                for x in 0..<cells {
                    let dx = Double(x) + 0.5 - 100
                    let dy = Double(y) + 0.5 - 100
                    let wave = 3 * sin(2 * .pi * dy / 100)
                    if dx * cos(0.12) + dy * sin(0.12) - wave - 20 > 0 { luma[y * cells + x] = 200 }
                    if (x * 7 + y * 13) % 31 == 0 { luma[y * cells + x] -= 40 }
                }
            }
            let box = CGRect(x: 440, y: 160, width: 400, height: 400)
            let found = EdgeLineDetector.detect(
                grid: EdgeLineGrid(luma: luma, width: cells, height: cells, step: 2), box: box,
                normal: CGPoint(x: 1, y: 0))
            let state = EdgeLineState()
            state.update(found?.path ?? [])
            return state
        }()

        var body: some View {
            VStack(spacing: 4) {
                ZStack {
                    Color(white: 0.45)
                    EdgeLineOverlay(state: state, mapper: SetupPreviewPanel.Mapper())
                }
                .frame(width: SetupPreviewPanel.panel.width, height: SetupPreviewPanel.panel.height)
                .clipped()
                Text("Edge line (cyan) on a synthetic edge").font(.caption).foregroundStyle(.white)
            }
        }
    }

    /// Every scene, two to a row, then the guide's extras.
    struct SetupPreviewSheet: View {
        var body: some View {
            let scenes = SetupPreviewPanel.Scene.allCases
            VStack(spacing: 12) {
                ForEach(0..<(scenes.count / 2), id: \.self) { row in
                    HStack(spacing: 12) {
                        SetupPreviewPanel(scene: scenes[row * 2])
                        SetupPreviewPanel(scene: scenes[row * 2 + 1])
                    }
                }
                GuideExtrasPanel()
            }
            .padding(16)
            .background(Color(white: 0.12))
        }
    }

    #Preview("Align clipped right") { SetupPreviewPanel(scene: .alignClippedRight) }
    #Preview("Align uneven") { SetupPreviewPanel(scene: .alignUneven) }
    #Preview("Align glare") { SetupPreviewPanel(scene: .alignGlare) }
    #Preview("Align passed") { SetupPreviewPanel(scene: .alignPassed) }
    #Preview("Focus turnOneWay") { SetupPreviewPanel(scene: .focusTurnOneWay) }
    #Preview("Focus passedPeak") { SetupPreviewPanel(scene: .focusPassedPeak) }
    #Preview("Focus focused") { SetupPreviewPanel(scene: .focusFocused) }
    #Preview("Focus needsSample") { SetupPreviewPanel(scene: .focusNeedsSample) }
    #Preview("Stage waitX") { SetupPreviewPanel(scene: .stageWaitX) }
    #Preview("Stage waitY") { SetupPreviewPanel(scene: .stageWaitY) }
    #Preview("Stage rejected") { SetupPreviewPanel(scene: .stageRejected) }
    #Preview("Stage start") { SetupPreviewPanel(scene: .stageStart) }
    #Preview("Stage nothing to follow") { SetupPreviewPanel(scene: .stageNothingToFollow) }
    #Preview("Stage done") { SetupPreviewPanel(scene: .stageDone) }
    #Preview("Paused alignment") { SetupPreviewPanel(scene: .pausedAlignment) }
    #Preview("Paused focus") { SetupPreviewPanel(scene: .pausedFocus) }
    #Preview("Edge line") { EdgeLinePreviewPanel() }
    #Preview("Guide extras") { GuideExtrasPanel() }
#endif
