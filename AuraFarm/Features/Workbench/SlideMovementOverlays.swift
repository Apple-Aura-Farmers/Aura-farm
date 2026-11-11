#if DEBUG
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
        var onTapTrail: () -> Void = {}

        var body: some View {
            ZStack {
                LiveFieldOutlines(model: model, mapping: mapping, mirrored: mirrored)
                LiveFieldCard(model: model)
                if model.fieldInfo.awaitingReview {
                    FieldReview(
                        info: model.fieldInfo, mapping: mapping, mirrored: mirrored,
                        onConfirm: { model.confirmField() },
                        onAdjust: { model.adjustField(to: $0) })
                } else {
                VStack {
                    HStack(alignment: .top) {
                        LiveStatusBanner(model: model)
                        Spacer()
                        LiveRecBadge(model: model)
                    }
                    Spacer()
                    HStack(alignment: .bottom) {
                        LiveSpeedMeter(model: model)
                            .frame(width: 140)
                        Spacer()
                        LiveTrail(model: model, mapping: mapping, mirrored: mirrored)
                            .frame(width: 140, height: 140)
                            .onTapGesture(perform: onTapTrail)
                    }
                }
                .padding(8)
                }
            }
        }
    }

    // MARK: - Pieces that read the model

    struct LiveStatusBanner: View {
        var model: SlideMovementLabModel
        var body: some View { StatusBanner(status: model.statusInfo.status) }
    }

    struct LiveSpeedMeter: View {
        var model: SlideMovementLabModel
        var body: some View { SpeedMeter(speedFraction: model.statusInfo.speedFraction) }
    }

    struct LiveTrail: View {
        var model: SlideMovementLabModel
        var mapping: ScreenMapping
        var mirrored: Bool
        var body: some View {
            SlideMovementTrail(info: model.trailInfo, mapping: mapping, mirrored: mirrored)
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

    struct LiveFieldOutlines: View {
        var model: SlideMovementLabModel
        var mapping: ScreenMapping
        var mirrored: Bool
        var body: some View {
            FieldOutlines(info: model.fieldInfo, mapping: mapping, mirrored: mirrored)
        }
    }

    // MARK: - Drawing from values

    /// The learned eyepiece mask as a faint red tint, and the rectangle registration looks in as
    /// a thin yellow outline, drawn over the preview through the chosen mapping and the
    /// preview's aspect fill. Rough: it is only as right as the mapping picked.
    struct FieldOutlines: View {
        var info: SlideMovementInfo.Field
        var mapping: ScreenMapping
        var mirrored: Bool

        var body: some View {
            Canvas { context, size in
                if let image = info.maskImage, info.maskExtent != .zero {
                    var layer = context
                    layer.transform = PreviewGeometry.transform(
                        frameSize: info.frameSize, viewSize: size, mapping: mapping,
                        mirrored: mirrored)
                    layer.draw(
                        layer.resolve(Image(decorative: image, scale: 1).interpolation(.none)),
                        in: info.maskExtent)
                }
                if let rect = info.registrationRect {
                    let placed = PreviewGeometry.rect(
                        of: rect, frameSize: info.frameSize, viewSize: size, mapping: mapping,
                        mirrored: mirrored)
                    context.stroke(Path(placed), with: .color(.yellow), lineWidth: 1)
                }
            }
            .allowsHitTesting(false)
        }
    }

    struct LiveFieldCard: View {
        var model: SlideMovementLabModel
        var body: some View { FieldCard(state: model.fieldInfo.state) }
    }

    /// Says what the eyepiece field is up to: learning, or not found.
    struct FieldCard: View {
        var state: FieldState?

        var body: some View {
            switch state {
            case .learning(let progress):
                card(colour: .black.opacity(0.7)) {
                    Text("Finding the eyepiece field…").font(.headline)
                    Text("Slowly move the slide around so every part of the field is lit")
                        .font(.caption)
                    ProgressView(value: progress).tint(.white)
                }
            case .untrusted:
                card(colour: .orange) {
                    Text("Couldn't find the eyepiece field.").font(.headline)
                    Text(
                        "Using the centre of the frame. Check the light and tap Re-detect field."
                    )
                    .font(.caption)
                }
            default:
                EmptyView()
            }
        }

        private func card<Content: View>(
            colour: Color, @ViewBuilder content: () -> Content
        ) -> some View {
            VStack(spacing: 6, content: content)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(12)
                .frame(maxWidth: 260)
                .background(colour, in: RoundedRectangle(cornerRadius: 12))
                .allowsHitTesting(false)
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
            }
        }

        private var symbol: String {
            switch status {
            case .starting: "hourglass"
            case .tracking: "checkmark.circle.fill"
            case .tooFast: "tortoise.fill"
            case .lost: "exclamationmark.triangle.fill"
            }
        }

        private var subtitle: String? {
            switch status {
            case .tooFast: "Slow down"
            case .lost: "Move slowly back"
            default: nil
            }
        }

        private var colour: Color {
            switch status {
            case .starting: .gray
            case .tracking: .green
            case .tooFast: .orange
            case .lost: .red
            }
        }
    }

    /// A bar with green, orange and red zones and a needle. The scale ends at twice the
    /// too-fast speed.
    struct SpeedMeter: View {
        var speedFraction: Double
        var thresholds = MovementIndicatorThresholds()

        var body: some View {
            let end = thresholds.tooFastSpeedFraction * 2
            let comfortable = min(thresholds.comfortableSpeedFraction / end, 1)
            let tooFast = min(thresholds.tooFastSpeedFraction / end, 1)
            let needle = min(max(speedFraction / end, 0), 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Speed").font(.caption2.bold()).foregroundStyle(.white)
                GeometryReader { proxy in
                    let width = proxy.size.width
                    ZStack(alignment: .leading) {
                        HStack(spacing: 0) {
                            Rectangle().fill(.green).frame(width: width * comfortable)
                            Rectangle().fill(.orange).frame(width: width * (tooFast - comfortable))
                            Rectangle().fill(.red)
                        }
                        .clipShape(Capsule())
                        Rectangle().fill(.white)
                            .frame(width: 4, height: 22)
                            .shadow(radius: 1)
                            .offset(x: width * needle - 2)
                    }
                }
                .frame(height: 22)
            }
            .padding(8)
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
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
            TrailScale.reach(for: info.trail + [info.startPoint].compactMap { $0 })
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
                Text("grid = 1 frame").font(.system(size: 9, weight: .bold)).foregroundColor(.white),
                at: CGPoint(x: size.width - 38, y: 10))

            if let start = info.startPoint {
                let home = place(start)
                let radius = thresholds.homeZoneFrames * scale
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
                var line = Path()
                line.move(to: place(info.trail[0]))
                for point in info.trail.dropFirst() { line.addLine(to: place(point)) }
                context.stroke(line, with: .color(.yellow), lineWidth: 2)
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
                state: .ready(mask), maskImage: mask.tintImage(),
                maskExtent: CGRect(x: 0, y: 0, width: 1280, height: 720),
                registrationRect: mask.registrationRect,
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
                FieldOutlines(info: PreviewData.field, mapping: mapping, mirrored: mirrored)
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
#endif
