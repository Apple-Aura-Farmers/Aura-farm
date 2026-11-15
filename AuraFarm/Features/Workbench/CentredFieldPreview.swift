#if DEBUG
    import SwiftUI

    /// A synthetic camera frame with the eyepiece field toward the bottom left, shown as the lab
    /// shows it with and without "Centre the field": the same picture, box outline and guide
    /// cross, drawn through the same `FramePreviewConverter.fitTransform` the live view uses.
    /// There is no camera here, so the layer's conversion is a plain scale of the frame.
    struct CentredFieldDemo: View {
        /// The synthetic frame, px. The field is low and to the left of the frame's middle.
        static let frameSize = CGSize(width: 1280, height: 720)
        static let field = FieldCircle(centre: CGPoint(x: 420, y: 500), radius: 190)
        private static let panel = CGSize(width: 400, height: 225)

        var body: some View {
            VStack(spacing: 12) {
                panelView(centred: false, title: "Uncropped")
                panelView(centred: true, title: "Centred")
            }
            .padding(16)
            .background(Color(white: 0.12))
        }

        private func panelView(centred: Bool, title: String) -> some View {
            let scale = Self.panel.width / Self.frameSize.width
            let crop = FieldCentring.cropRect(for: Self.field, frameSize: Self.frameSize)
            let display =
                centred
                ? FramePreviewConverter.fitTransform(
                    of: CGRect(
                        x: crop.minX * scale, y: crop.minY * scale, width: crop.width * scale,
                        height: crop.height * scale),
                    in: Self.panel)
                : .identity
            /// A frame point in the displayed space.
            func place(_ point: CGPoint) -> CGPoint {
                CGPoint(x: point.x * scale, y: point.y * scale).applying(display)
            }
            let box = Self.field.mask(frameSize: Self.frameSize).registrationRect ?? .zero
            let boxOnScreen = CGRect(
                origin: place(box.origin),
                size: CGSize(width: box.width * scale * display.a, height: box.height * scale * display.a))
            let side = boxOnScreen.width
            return VStack(spacing: 4) {
                ZStack {
                    picture
                        .frame(width: Self.panel.width, height: Self.panel.height)
                        .scaleEffect(display.a, anchor: .topLeading)
                        .offset(x: display.tx, y: display.ty)
                    // Marks, drawn in the displayed space and not scaled.
                    Canvas { context, _ in
                        // The tint covers the picture only, as the real one covers the frame.
                        var ring = Path(
                            CGRect(
                                origin: place(.zero),
                                size: CGSize(
                                    width: Self.panel.width * display.a,
                                    height: Self.panel.height * display.a)))
                        let centre = place(Self.field.centre)
                        let radius = Self.field.radius * scale * display.a
                        ring.addEllipse(
                            in: CGRect(
                                x: centre.x - radius, y: centre.y - radius, width: radius * 2,
                                height: radius * 2))
                        context.fill(ring, with: .color(.red.opacity(0.35)), style: FillStyle(eoFill: true))
                        context.stroke(Path(boxOnScreen), with: .color(.yellow), lineWidth: 1)
                    }
                    // The guide: the centre cross and a target cross 0.6 field to the right.
                    TargetCross()
                        .stroke(.white, lineWidth: 2)
                        .frame(width: 22, height: 22)
                        .position(x: boxOnScreen.midX, y: boxOnScreen.midY)
                    TargetCross()
                        .stroke(.green, lineWidth: 2)
                        .frame(width: 22, height: 22)
                        .position(x: boxOnScreen.midX + 0.6 * side, y: boxOnScreen.midY)
                    Text("Move right")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.7), in: Capsule())
                        .position(x: Self.panel.width / 2, y: Self.panel.height - 14)
                }
                .frame(width: Self.panel.width, height: Self.panel.height)
                .clipped()
                .overlay(Rectangle().stroke(.white.opacity(0.5), lineWidth: 1))
                Text(title).font(.caption).foregroundStyle(.white)
            }
        }

        /// A stand-in for the camera picture: a grid and some dots, so a shift or a scale shows.
        private var picture: some View {
            Canvas { context, size in
                let scale = size.width / Self.frameSize.width
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.55)))
                var path = Path()
                for x in stride(from: 0.0, through: Self.frameSize.width, by: 80) {
                    path.move(to: CGPoint(x: x * scale, y: 0))
                    path.addLine(to: CGPoint(x: x * scale, y: size.height))
                }
                for y in stride(from: 0.0, through: Self.frameSize.height, by: 80) {
                    path.move(to: CGPoint(x: 0, y: y * scale))
                    path.addLine(to: CGPoint(x: size.width, y: y * scale))
                }
                context.stroke(path, with: .color(.white.opacity(0.35)), lineWidth: 0.5)
                var seed: UInt64 = 5
                for _ in 0..<160 {
                    seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                    let x = Double((seed >> 33) % 1280)
                    let y = Double((seed >> 12) % 720)
                    context.fill(
                        Path(ellipseIn: CGRect(x: x * scale - 2, y: y * scale - 2, width: 4, height: 4)),
                        with: .color(.brown))
                }
            }
        }
    }

    #Preview {
        CentredFieldDemo()
    }
#endif
