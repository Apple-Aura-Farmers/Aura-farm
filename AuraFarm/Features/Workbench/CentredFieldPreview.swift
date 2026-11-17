#if DEBUG
    import SwiftUI

    /// A synthetic camera frame as the lab shows the field once it is confirmed: the picture
    /// is the circle's bounding square, full width, with everything outside the circle dark, the
    /// registration box turning with the picture and the guide's cross and arrow upright. Three
    /// cases: an off-centre circle (low and to the left), a centred circle, and a stage tilted 10
    /// degrees, straightened so a column's dots stand vertical and the guide's arrow points
    /// straight up. There is no camera here, so the layer's conversion is a plain scale of the
    /// frame, letterboxed in the square the way `.resizeAspect` lays it out.
    struct CentredFieldDemo: View {
        /// The synthetic frame, px.
        static let frameSize = CGSize(width: 1280, height: 720)
        private static let side = 300.0

        enum Case: CaseIterable {
            case offCentre, centred, straightened

            var title: String {
                switch self {
                case .offCentre: "Off-centre circle (bottom left), centred and square"
                case .centred: "Circle already centred"
                case .straightened: "Stage tilted 10°, straightened: column vertical"
                }
            }

            var circle: FieldCircle {
                switch self {
                case .offCentre: FieldCircle(centre: CGPoint(x: 420, y: 500), radius: 190)
                case .centred, .straightened: FieldCircle(centre: CGPoint(x: 640, y: 360), radius: 250)
                }
            }

            var tiltDegrees: Double { self == .straightened ? 10 : 0 }
        }

        var body: some View {
            VStack(spacing: 12) {
                ForEach(Case.allCases, id: \.title) { panel($0) }
            }
            .padding(16)
            .background(Color(white: 0.12))
        }

        /// The stage axes for a tilt: the X knob 10 degrees from screen x, the Y knob about 9
        /// degrees off screen y (a little skew, as in Test 4).
        static func axes(tiltDegrees: Double) -> StageAxes {
            guard tiltDegrees != 0 else { return .identity }
            let x = tiltDegrees * .pi / 180
            let y = (90 + tiltDegrees - 1.6) * .pi / 180
            return StageAxes(
                xDirection: CGPoint(x: cos(x), y: sin(x)),
                yDirection: CGPoint(x: cos(y), y: sin(y))) ?? .identity
        }

        private func panel(_ scene: Case) -> some View {
            let side = Self.side
            let scale = side / Self.frameSize.width
            // `.resizeAspect`: the whole frame, letterboxed in the square.
            let offset = (side - Self.frameSize.height * scale) / 2
            func layerPoint(_ point: CGPoint) -> CGPoint {
                CGPoint(x: point.x * scale, y: point.y * scale + offset)
            }
            let circle = scene.circle
            let crop = FieldCentring.cropRect(for: circle, frameSize: Self.frameSize)
            let cropOrigin = layerPoint(crop.origin)
            let axes = Self.axes(tiltDegrees: scene.tiltDegrees)
            let display = FramePreviewConverter.displayTransform(
                crop: CGRect(
                    origin: cropOrigin,
                    size: CGSize(width: crop.width * scale, height: crop.height * scale)),
                centre: layerPoint(circle.centre), straightening: axes.straightening,
                viewSize: CGSize(width: side, height: side))
            let box = circle.mask(frameSize: Self.frameSize).registrationRect ?? .zero
            let yDirection = axes.yDirection
            return VStack(spacing: 4) {
                ZStack {
                    Canvas { context, size in
                        context.clip(to: Path(CGRect(origin: .zero, size: size)))
                        // The picture, in the layer's own space, through the display transform.
                        var picture = context
                        picture.concatenate(display)
                        picture.fill(
                            Path(CGRect(x: 0, y: offset, width: side, height: side - offset * 2)),
                            with: .color(Color(white: 0.55)))
                        var grid = Path()
                        for x in stride(from: 0.0, through: Self.frameSize.width, by: 80) {
                            grid.move(to: layerPoint(CGPoint(x: x, y: 0)))
                            grid.addLine(to: layerPoint(CGPoint(x: x, y: Self.frameSize.height)))
                        }
                        for y in stride(from: 0.0, through: Self.frameSize.height, by: 80) {
                            grid.move(to: layerPoint(CGPoint(x: 0, y: y)))
                            grid.addLine(to: layerPoint(CGPoint(x: Self.frameSize.width, y: y)))
                        }
                        picture.stroke(grid, with: .color(.white.opacity(0.3)), lineWidth: 0.5)
                        // A column of spots along the stage's Y axis, tilted in the frame.
                        for step in -4...4 {
                            let spot = CGPoint(
                                x: circle.centre.x + Double(step) * 0.5 * circle.radius
                                    * Double(yDirection.x),
                                y: circle.centre.y + Double(step) * 0.5 * circle.radius * Double(yDirection.y)
                            )
                            let at = layerPoint(spot)
                            picture.fill(
                                Path(ellipseIn: CGRect(x: at.x - 4, y: at.y - 4, width: 8, height: 8)),
                                with: .color(.brown))
                        }
                        // Everything outside the circle dark: an even-odd fill of the view less
                        // the circle.
                        let corner = layerPoint(
                            CGPoint(x: circle.centre.x - circle.radius, y: circle.centre.y - circle.radius))
                        var outside = Path(CGRect(origin: .zero, size: size))
                        outside.addPath(
                            Path(
                                ellipseIn: CGRect(
                                    origin: corner,
                                    size: CGSize(
                                        width: circle.radius * 2 * scale, height: circle.radius * 2 * scale))
                            ).applying(display))
                        context.fill(outside, with: .color(.black), style: FillStyle(eoFill: true))
                        // The registration box turns with the picture.
                        var outline = Path()
                        outline.addLines(
                            [
                                CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                                CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY),
                            ].map { layerPoint($0).applying(display) })
                        outline.closeSubpath()
                        context.stroke(outline, with: .color(.yellow), lineWidth: 1)
                    }
                    // The guide, upright: the centre cross, a target cross one field ahead and
                    // the arrow of the column's heading.
                    TargetCross()
                        .stroke(.white, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    TargetCross()
                        .stroke(.green, lineWidth: 2)
                        .frame(width: 22, height: 22)
                        .offset(y: -side * 0.3)
                    ArrowShape()
                        .fill(.white)
                        .frame(width: 44, height: 16)
                        .rotationEffect(.degrees(-90))
                        .offset(y: -side * 0.42)
                }
                .frame(width: side, height: side)
                .clipped()
                .overlay(Rectangle().stroke(.white.opacity(0.5), lineWidth: 1))
                Text(scene.title).font(.caption).foregroundStyle(.white)
            }
        }
    }

    #Preview {
        CentredFieldDemo()
    }
#endif
