#if DEBUG
    import AVFoundation
    import SwiftUI

    /// The colour a label is shown in, on its chip and its button.
    func slideLabLabelColor(_ label: String) -> Color {
        switch label {
        case "sample": .green
        case "blank": .blue
        case "blurry": .orange
        default: .gray
        }
    }

    /// Everything drawn over the lab's camera strip. Each piece is a small view of its own that
    /// reads only what it shows from the model, so the trail and the outlines are not redrawn
    /// when only the text readouts change.
    struct SlideMovementOverlays: View {
        var model: SlideMovementLabModel
        var mapping: ScreenMapping
        var mirrored: Bool
        var previewLayer: AVCaptureVideoPreviewLayer?
        /// How the picture is shown (the field centred); every mark anchored to the picture is
        /// drawn through it. The text and the trail are not.
        var display = CGAffineTransform.identity
        /// The picture is shown as the field's square: everything outside the circle is dark.
        var centred = false
        var onTapTrail: () -> Void = {}
        /// "In focus – empty area" on the focus-pause banner; nil (the default) hides the button.
        var onEmptyArea: (() -> Void)?
        /// The automated stage is on: the lab's stage step needs no knob turning.
        var automatedStage = false

        var body: some View {
            ZStack {
                LiveFieldOutlines(
                    model: model, previewLayer: previewLayer, display: display,
                    darkensOutside: centred)
                LiveFieldCard(model: model)
                if model.setupInfo.step == .align || model.setupInfo.step == .focus {
                    // Steps 1 and 2: nothing is learned or tracked yet.
                    LiveSetupOverlay(
                        model: model, previewLayer: previewLayer, automatedStage: automatedStage,
                        display: display)
                } else if model.fieldInfo.awaitingReview {
                    FieldReview(
                        info: model.fieldInfo,
                        converter: FramePreviewConverter(
                            layer: previewLayer, frameSize: model.fieldInfo.frameSize),
                        onConfirm: { model.confirmField() },
                        onAdjust: { model.adjustField(to: $0) })
                    VStack {
                        SetupStepIndicator(step: .field).padding(8)
                        Spacer()
                    }
                } else if model.setupInfo.step == .stage {
                    // Step 4: the axes are measured from the guide's own position, so the
                    // geometry is hosted even with the dry run off.
                    GuideGeometryHost(model: model, previewLayer: previewLayer, display: display)
                    LiveSetupOverlay(
                        model: model, previewLayer: previewLayer, automatedStage: automatedStage,
                        display: display)
                } else {
                    if model.guideDryRun {
                        GuideGeometryHost(model: model, previewLayer: previewLayer, display: display)
                        if model.showsDetections {
                            let mapper = FramePreviewConverter(
                                layer: previewLayer, frameSize: model.fieldInfo.frameSize,
                                display: display)
                            DetectionBoxes(info: model.liveBoxes) { mapper?.viewPolygon(of: $0) ?? [] }
                        }
                        LiveGuideOverlay(state: model.overlayState)
                        LiveEdgeFeedback(model: model, state: model.overlayState)
                        // Below the ✓ count at the top of the guide area.
                        VStack {
                            HelperCountChip(info: model.countInfo).padding(.top, 40)
                            Spacer()
                        }
                        .allowsHitTesting(false)
                        EdgeLineOverlay(
                            state: model.edgeLineState,
                            mapper: FramePreviewConverter(
                                layer: previewLayer, frameSize: model.fieldInfo.frameSize,
                                display: display))
                    }
                    PausedOverlay(
                        monitor: model.setupInfo.monitor,
                        mapper: FramePreviewConverter(
                            layer: previewLayer, frameSize: model.fieldInfo.frameSize,
                            display: display),
                        onResumeAnyway: { model.resumeFocusAnyway() }, onEmptyArea: onEmptyArea)
                    VStack {
                        HStack(alignment: .top) {
                            // The picture stays clear while the guide is drawing on it.
                            if !model.guideDryRun { LiveStatusBanner(model: model) }
                            Spacer()
                            ThermalBadge(state: model.thermalState)
                            LiveRecBadge(model: model)
                        }
                        Spacer()
                        HStack(alignment: .bottom) {
                            // Stays on with the guide: it says whether the speed is right.
                            LiveSpeedMeter(model: model)
                                .frame(width: 140)
                            Spacer()
                            LiveTrail(model: model, mapping: mapping, mirrored: mirrored)
                                .frame(width: 140, height: 140)
                                .onTapGesture(perform: onTapTrail)
                        }
                        // Leaves room for the guide's line along the bottom.
                        .padding(.bottom, model.guideDryRun ? 56 : 0)
                    }
                    .padding(8)
                    if model.setupInfo.step == .field {
                        VStack {
                            SetupStepIndicator(step: .field).padding(8)
                            Spacer()
                        }
                    }
                }
                if let toast = model.markToast {
                    Text(toast)
                        .font(.subheadline.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.75), in: Capsule())
                        .foregroundStyle(.white)
                        .transition(.opacity)
                }
            }
            .animation(.default, value: model.markToast)
        }
    }

    // MARK: - Pieces that read the model

    /// The edge buttons, from values: "✓ Edge" and "✗ Not an edge" while an attached line is at the
    /// cross and the helper is asked, and "Mark edge here" while an edge is looked for.
    struct EdgeFeedbackBar: View {
        var asks: Bool
        var canMark: Bool
        var onAnswer: (EdgeFeedback) -> Void = { _ in }

        var body: some View {
            VStack(spacing: 8) {
                Spacer()
                if asks {
                    HStack(spacing: 12) {
                        Button("✓ Edge") { onAnswer(.yes) }.tint(.green)
                        Button("✗ Not an edge") { onAnswer(.no) }.tint(.red)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                if canMark {
                    Button("Mark edge here") { onAnswer(.mark) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.white)
                }
            }
            .padding(.bottom, 64)
        }
    }

    /// Reads the guide overlay's state and answers to the model.
    struct LiveEdgeFeedback: View {
        var model: SlideMovementLabModel
        var state: GuideOverlayState

        var body: some View {
            EdgeFeedbackBar(
                asks: state.asksEdge, canMark: state.canMarkEdge,
                onAnswer: { model.edgeFeedback($0) })
        }
    }

    struct LiveStatusBanner: View {
        var model: SlideMovementLabModel
        var body: some View { StatusBanner(status: model.speedState.status) }
    }

    struct LiveTrail: View {
        var model: SlideMovementLabModel
        var mapping: ScreenMapping
        var mirrored: Bool
        var body: some View {
            VStack(spacing: 3) {
                SlideMovementTrail(info: model.trailInfo, mapping: mapping, mirrored: mirrored)
                // Under the map: the types present, with colour and count; the top 3 when small.
                if !model.trailInfo.life.isEmpty {
                    LifeLegendView(
                        counts: Dictionary(grouping: model.trailInfo.life, by: \.label).mapValues(\.count),
                        limit: 3)
                }
            }
        }
    }

    /// The phone's thermal state, a small badge: nothing depends on it yet (no heat guard).
    struct ThermalBadge: View {
        var state: String

        private var colour: Color {
            switch state {
            case "fair": .yellow
            case "serious": .orange
            case "critical": .red
            default: .green
            }
        }

        var body: some View {
            HStack(spacing: 4) {
                Image(systemName: "thermometer.medium")
                Text(state)
            }
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.6), in: Capsule())
            .foregroundStyle(colour)
        }
    }

    struct LiveRecBadge: View {
        var model: SlideMovementLabModel
        var body: some View {
            if model.isLogging {
                RecBadge(
                    elapsed: model.readouts.elapsedLogSeconds, rowCount: model.rowCount,
                    label: model.label)
            }
        }
    }

    struct RecBadge: View {
        var elapsed: Double
        var rowCount: Int
        var label: String

        var body: some View {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(.red).frame(width: 10, height: 10)
                    Text("REC \(clock) · \(rowCount) rows")
                        .font(.footnote.bold().monospacedDigit())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.black.opacity(0.65), in: Capsule())
                .foregroundStyle(.white)
                if !label.isEmpty {
                    Text(label.uppercased())
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(slideLabLabelColor(label), in: Capsule())
                        .foregroundStyle(.white)
                }
            }
        }

        private var clock: String {
            let total = Int(elapsed)
            return String(format: "%02d:%02d", total / 60, total % 60)
        }
    }

    struct StatusBanner: View {
        var status: MovementIndicators.Status

        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.title2)
                VStack(alignment: .leading, spacing: 0) {
                    Text(word).font(.title3.weight(.heavy))
                    if let subtitle {
                        Text(subtitle).font(.caption.bold())
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(colour, in: Capsule())
            .foregroundStyle(.white)
        }

        private var word: String {
            switch status {
            case .starting: "Starting"
            case .tracking: "TRACKING"
            case .tooFast: "TOO FAST"
            case .lost: "LOST"
            case .noDetail: "NO DETAIL"
            }
        }

        private var symbol: String {
            switch status {
            case .starting: "hourglass"
            case .tracking: "checkmark.circle.fill"
            case .tooFast: "tortoise.fill"
            case .lost: "exclamationmark.triangle.fill"
            case .noDetail: "eye.slash"
            }
        }

        private var subtitle: String? {
            switch status {
            case .tooFast: "Slow down"
            case .lost: "Move slowly back"
            case .noDetail: "Nothing to follow here. Move back over the sample."
            default: nil
            }
        }

        private var colour: Color {
            switch status {
            case .starting: .gray
            case .tracking: .green
            case .tooFast: .orange
            case .lost: .red
            case .noDetail: Color(red: 0.36, green: 0.45, blue: 0.58)
            }
        }
    }

    /// The recent position as a line with a dot at the current one, drawn through the chosen
    /// screen mapping, with a hop ring, the start marker and its home zone, the hops that were
    /// tracked and where tracking was lost, a one-frame grid, and a legend showing where the
    /// frame's axes point on screen.
    struct SlideMovementTrail: View {
        var info: SlideMovementInfo.Trail
        var mapping: ScreenMapping
        var mirrored: Bool
        var thresholds = MovementIndicatorThresholds()

        @State private var flashing = false

        /// The frames from the centre to the edge of the box. Grows when the view travels far,
        /// so the whole move stays on screen.
        private var reach: Double {
            var points = info.trail + [info.startPoint].compactMap { $0 }
            // With life on the map the whole slip stays in view: the dots, the captured spots and
            // the edges.
            if !info.life.isEmpty {
                points += info.life.map(\.point) + info.guideCaptured + info.edgePoints
                points += info.predicted.flatMap { [$0.from, $0.to] }
            }
            return TrailScale.reach(for: points)
        }

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.5))
                Canvas { context, size in draw(&context, size) }
                RoundedRectangle(cornerRadius: 10)
                    .trim(from: 0, to: info.hopProgress)
                    .stroke(flashing ? .white : .cyan, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .padding(2)
            }
            .task(id: info.hopCount) {
                guard info.hopCount > 0 else { return }
                flashing = true
                try? await Task.sleep(for: .milliseconds(200))
                flashing = false
            }
        }

        private func draw(_ context: inout GraphicsContext, _ size: CGSize) {
            let reach = reach
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let scale = min(size.width, size.height) / 2 / reach
            func place(_ point: CGPoint) -> CGPoint {
                let moved = mapping.onScreen(point, mirrored: mirrored)
                return CGPoint(x: centre.x + moved.x * scale, y: centre.y + moved.y * scale)
            }

            // One line per whole frame in each direction, so a distance can be counted.
            let whole = Int(reach.rounded(.down))
            var grid = Path()
            for k in -whole...whole {
                let offset = Double(k) * scale
                grid.move(to: CGPoint(x: centre.x + offset, y: 0))
                grid.addLine(to: CGPoint(x: centre.x + offset, y: size.height))
                grid.move(to: CGPoint(x: 0, y: centre.y + offset))
                grid.addLine(to: CGPoint(x: size.width, y: centre.y + offset))
            }
            context.stroke(grid, with: .color(.white.opacity(0.2)), lineWidth: 1)
            var axes = Path()
            axes.move(to: CGPoint(x: 0, y: centre.y))
            axes.addLine(to: CGPoint(x: size.width, y: centre.y))
            axes.move(to: CGPoint(x: centre.x, y: 0))
            axes.addLine(to: CGPoint(x: centre.x, y: size.height))
            context.stroke(axes, with: .color(.white.opacity(0.5)), lineWidth: 1)
            context.draw(
                Text("grid = 1 field").font(.system(size: 9, weight: .bold)).foregroundColor(.white),
                at: CGPoint(x: size.width - 38, y: 10))

            // The guide's captured spots (green dots) and its current target (yellow ring).
            for point in info.guideCaptured {
                let spot = place(point)
                context.fill(
                    Path(ellipseIn: CGRect(x: spot.x - 3.5, y: spot.y - 3.5, width: 7, height: 7)),
                    with: .color(.green))
            }
            if let target = info.guideTarget {
                let spot = place(target)
                context.stroke(
                    Path(ellipseIn: CGRect(x: spot.x - 6, y: spot.y - 6, width: 12, height: 12)),
                    with: .color(.yellow), lineWidth: 2)
            }

            // The predicted top, bottom and right edges: faint dashed lines.
            for line in info.predicted {
                var path = Path()
                path.move(to: place(line.from))
                path.addLine(to: place(line.to))
                context.stroke(
                    path, with: .color(.cyan.opacity(0.45)),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }

            // Confirmed edge points and the organisms of the helper's count.
            for point in info.edgePoints {
                let spot = place(point)
                context.fill(
                    Path(ellipseIn: CGRect(x: spot.x - 2, y: spot.y - 2, width: 4, height: 4)),
                    with: .color(.cyan))
            }
            LifeDots.draw(info.life, in: &context, place: place)

            if let start = info.startPoint {
                let home = place(start)
                let radius = thresholds.homeZoneFields * scale
                context.stroke(
                    Path(
                        ellipseIn: CGRect(
                            x: home.x - radius, y: home.y - radius, width: radius * 2,
                            height: radius * 2)),
                    with: .color(.green), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                context.fill(
                    Path(ellipseIn: CGRect(x: home.x - 4, y: home.y - 4, width: 8, height: 8)),
                    with: .color(.green))
            }

            // Where a hop was tracked: a white dot. Where tracking was lost: a red cross.
            for point in info.hopPoints {
                let spot = place(point)
                context.fill(
                    Path(ellipseIn: CGRect(x: spot.x - 2.5, y: spot.y - 2.5, width: 5, height: 5)),
                    with: .color(.white))
            }
            for point in info.lostPoints {
                let spot = place(point)
                var cross = Path()
                cross.move(to: CGPoint(x: spot.x - 4, y: spot.y - 4))
                cross.addLine(to: CGPoint(x: spot.x + 4, y: spot.y + 4))
                cross.move(to: CGPoint(x: spot.x + 4, y: spot.y - 4))
                cross.addLine(to: CGPoint(x: spot.x - 4, y: spot.y + 4))
                context.stroke(cross, with: .color(.red), lineWidth: 2)
            }

            if let last = info.trail.last {
                // Followed stretches are solid; stretches over nothing to track are dashed.
                var solid = Path()
                var dashed = Path()
                for index in info.trail.indices.dropFirst() {
                    let blind = info.blind.indices.contains(index) && info.blind[index]
                    if blind {
                        dashed.move(to: place(info.trail[index - 1]))
                        dashed.addLine(to: place(info.trail[index]))
                    } else {
                        solid.move(to: place(info.trail[index - 1]))
                        solid.addLine(to: place(info.trail[index]))
                    }
                }
                context.stroke(solid, with: .color(.yellow), lineWidth: 2)
                context.stroke(
                    dashed, with: .color(.yellow.opacity(0.7)),
                    style: StrokeStyle(lineWidth: 2, dash: [3, 4]))
                let dot = place(last)
                context.fill(
                    Path(ellipseIn: CGRect(x: dot.x - 5, y: dot.y - 5, width: 10, height: 10)),
                    with: .color(.red))
            }

            legend(&context, size)
        }

        /// Short arrows from the bottom-left corner, drawn through the mapping.
        private func legend(_ context: inout GraphicsContext, _ size: CGSize) {
            let origin = CGPoint(x: 22, y: size.height - 22)
            for (axis, name) in [(CGPoint(x: 1, y: 0), "x"), (CGPoint(x: 0, y: 1), "y")] {
                let direction = mapping.onScreen(axis, mirrored: mirrored)
                let tip = CGPoint(x: origin.x + direction.x * 14, y: origin.y + direction.y * 14)
                var arrow = Path()
                arrow.move(to: origin)
                arrow.addLine(to: tip)
                context.stroke(arrow, with: .color(.white), lineWidth: 1.5)
                context.draw(
                    Text(name).font(.system(size: 9, weight: .bold)).foregroundColor(.white),
                    at: CGPoint(x: origin.x + direction.x * 20, y: origin.y + direction.y * 20))
            }
        }
    }

    // MARK: - Previews

    private enum PreviewData {
        /// A mask learned from one synthetic frame: a bright disc inside a dark ring.
        static var field: SlideMovementInfo.Field {
            let width = 160
            let height = 90
            var builder = FieldMaskBuilder(
                width: 1280, height: 720, thresholds: .init(framesToLearn: 1))
            let luma = (0..<(width * height)).map { index -> UInt8 in
                let dx = Double(index % width) - 80
                let dy = Double(index / width) - 45
                return hypot(dx, dy) <= 41 ? 180 : 4
            }
            builder.add(luma: luma, gridWidth: width, gridHeight: height)
            guard let mask = builder.result() else { return .init() }
            return .init(
                state: .ready(mask), registrationRect: mask.registrationRect,
                frameSize: CGSize(width: 1280, height: 720))
        }
    }

    /// The overlays driven by fixed fake values, so they can be checked without a camera.
    private struct PreviewStrip: View {
        var status: MovementIndicators.Status
        var speed: Double
        var mapping: ScreenMapping
        var mirrored = false

        var body: some View {
            ZStack {
                FieldOutlines(info: PreviewData.field, converter: nil)
                if status == .lost { FieldCard(state: .learning(progress: 0.4)) }
                VStack {
                    HStack(alignment: .top) {
                        StatusBanner(status: status)
                        Spacer()
                        RecBadge(elapsed: 83, rowCount: 812, label: "sample")
                    }
                    Spacer()
                    HStack(alignment: .bottom) {
                        SpeedMeter(speedFraction: speed).frame(width: 140)
                        Spacer()
                        SlideMovementTrail(
                            info: .init(
                                trail: (0..<60).map {
                                    CGPoint(x: Double($0) * 0.04, y: sin(Double($0) / 8) * 0.3)
                                },
                                hopPoints: [CGPoint(x: 0.6, y: 0.2), CGPoint(x: 1.4, y: 0.3)],
                                lostPoints: status == .lost ? [CGPoint(x: 2.0, y: -0.2)] : [],
                                startPoint: .zero, hopProgress: 0.6, hopCount: 2),
                            mapping: mapping, mirrored: mirrored
                        )
                        .frame(width: 140, height: 140)
                    }
                }
                .padding(8)
            }
            .frame(height: 340)
            .background(Color.gray)
        }
    }

    #Preview("Tracking") { PreviewStrip(status: .tracking, speed: 0.05, mapping: .asIs) }
    #Preview("Too fast") { PreviewStrip(status: .tooFast, speed: 0.22, mapping: .rotateRight) }
    #Preview("Lost") {
        PreviewStrip(status: .lost, speed: 0.02, mapping: .asIs, mirrored: true)
    }

    /// The trail mini-map with the predicted top, bottom and right edges drawn faint and dashed.
    #Preview("Trail map: predicted edges") {
        SlideMovementTrail(
            info: .init(
                trail: (0..<40).map { CGPoint(x: Double($0) * 0.05, y: -2.0 + Double($0) * 0.1) },
                startPoint: .zero, guideCaptured: [CGPoint(x: 0.4, y: -1.5), CGPoint(x: 0.4, y: -0.7)],
                predicted: [
                    PredictedTrailLine(
                        kind: .top, from: CGPoint(x: -0.6, y: -2.4), to: CGPoint(x: 3.4, y: -2.4)),
                    PredictedTrailLine(
                        kind: .bottom, from: CGPoint(x: -0.6, y: 2.4), to: CGPoint(x: 3.4, y: 2.4)),
                    PredictedTrailLine(
                        kind: .right, from: CGPoint(x: 3.4, y: -2.4), to: CGPoint(x: 3.4, y: 2.4)),
                ]),
            mapping: .asIs, mirrored: false
        )
        .frame(width: 240, height: 240)
        .background(Color.gray)
    }

    /// The mini-map with about 60 dots of 6 types, its legend (top 3) under it.
    #Preview("Mini-map: life dots") {
        let labels = ["Volvox", "Nematode", "Euglenoid", "Arcellinida", "Digononta", "Rotifer"]
        var life: [RunMapOrganism] = []
        for index in 0..<60 {
            let x = Double((index * 37) % 50) / 12 - 2
            let y = Double((index * 53) % 38) / 10 - 1.9
            life.append(
                RunMapOrganism(
                    label: labels[index % 6], x: x, y: y, column: index / 10 + 1,
                    seconds: Double(index)))
        }
        var trail: [CGPoint] = []
        for index in 0..<40 {
            trail.append(CGPoint(x: Double(index) * 0.05 - 1, y: Double(index) * 0.08 - 1.5))
        }
        let top = PredictedTrailLine(
            kind: .top, from: CGPoint(x: -2, y: -2), to: CGPoint(x: 2.4, y: -2))
        let bottom = PredictedTrailLine(
            kind: .bottom, from: CGPoint(x: -2, y: 2), to: CGPoint(x: 2.4, y: 2))
        var info = SlideMovementInfo.Trail()
        info.trail = trail
        info.startPoint = .zero
        info.predicted = [top, bottom]
        info.life = life
        let counts = Dictionary(grouping: life, by: \.label).mapValues(\.count)
        return VStack(spacing: 3) {
            SlideMovementTrail(info: info, mapping: .asIs, mirrored: false)
            LifeLegendView(counts: counts, limit: 3)
        }
        .frame(width: 180, height: 200)
        .background(Color.gray)
    }

    #Preview("Thermal badge: each state") {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(["nominal", "fair", "serious", "critical"], id: \.self) { ThermalBadge(state: $0) }
        }
        .padding()
        .background(.gray)
    }
#endif
