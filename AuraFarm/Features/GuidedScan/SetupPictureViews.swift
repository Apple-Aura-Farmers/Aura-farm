import AVFoundation
import SwiftUI

struct LiveFieldOutlines: View {
    var model: ScanEngine
    var previewLayer: AVCaptureVideoPreviewLayer?
    var display = CGAffineTransform.identity
    /// The picture is shown as the field's square: everything outside the circle is dark.
    var darkensOutside = false
    var body: some View {
        FieldOutlines(
            info: model.fieldInfo,
            converter: FramePreviewConverter(
                layer: previewLayer, frameSize: model.fieldInfo.frameSize, display: display),
            darkensOutside: darkensOutside)
    }
}

// MARK: - Drawing from values

/// The learned eyepiece mask as a faint red tint (or, when the picture is shown as the
/// field's square, everything outside the circle dark: an even-odd fill of the view less the
/// circle), and the rectangle registration looks in as a thin yellow outline that turns with
/// the picture, drawn over the preview with the preview layer's own conversion from frame
/// pixels. Nothing is drawn without a converter (a preview with no camera).
struct FieldOutlines: View {
    var info: SlideMovementInfo.Field
    var converter: FramePreviewConverter?
    var darkensOutside = false

    var body: some View {
        Canvas { context, size in
            guard let converter else { return }
            if darkensOutside, let mask = info.state?.mask, let circle = FieldCircle(fitting: mask) {
                var outside = Path(CGRect(origin: .zero, size: size))
                let box = converter.layerRect(
                    of: CGRect(
                        x: circle.centre.x - circle.radius, y: circle.centre.y - circle.radius,
                        width: circle.radius * 2, height: circle.radius * 2))
                outside.addPath(Path(ellipseIn: box).applying(converter.display))
                context.fill(outside, with: .color(.black), style: FillStyle(eoFill: true))
            } else if !darkensOutside {
                for rect in info.state?.mask?.eyepieceRects() ?? [] {
                    context.fill(
                        Path(converter.viewRect(of: rect)), with: .color(.red.opacity(0.35)))
                }
            }
            // Circle-only view: the yellow box stays measured, just not shown.
            if !darkensOutside, let rect = info.registrationRect {
                var outline = Path()
                outline.addLines(converter.viewPolygon(of: rect))
                outline.closeSubpath()
                context.stroke(outline, with: .color(.yellow), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Measures the preview's axes and sizes for the guide overlay and hands them to the model.
/// Draws nothing. Rebuilds when the box, the frame size or the view size changes.
struct GuideGeometryHost: View {
    var model: ScanEngine
    var previewLayer: AVCaptureVideoPreviewLayer?
    /// The centring transform: the axes, the centre and the size of a field are measured in
    /// the displayed space, the one the marks are drawn in.
    var display = CGAffineTransform.identity

    private struct Key: Equatable {
        var box: CGRect?
        var frameSize: CGSize
        var viewSize: CGSize
        var hasLayer: Bool
        var openShare: Double?
        var display: CGAffineTransform
    }

    /// The length, in frame pixels, of the two probe vectors the axes are measured with.
    static let probePixels = 100.0

    var body: some View {
        GeometryReader { proxy in
            let info = model.fieldInfo
            Color.clear
                .task(
                    id: Key(
                        box: info.registrationRect, frameSize: info.frameSize,
                        viewSize: proxy.size, hasLayer: previewLayer != nil,
                        openShare: info.state?.openShare, display: display)
                ) {
                    model.setGuideGeometry(geometry(for: info))
                }
        }
        .allowsHitTesting(false)
    }

    private func geometry(for info: SlideMovementInfo.Field) -> GuideScreenGeometry? {
        guard
            let converter = FramePreviewConverter(
                layer: previewLayer, frameSize: info.frameSize, display: display)
        else { return nil }
        var circle: FieldCircle?
        if case .ready(let mask)? = info.state { circle = FieldCircle(fitting: mask) }
        return Self.geometry(
            using: converter, box: info.registrationRect ?? CGRect(origin: .zero, size: info.frameSize),
            circle: circle)
    }

    /// How the preview shows the box. The size of a field and of the field's radius come from
    /// the lengths of the probe vectors (`FrameToView.scale`), not from the bounding box of
    /// a rectangle, which grows when the picture is turned or sheared.
    static func geometry(
        using mapper: any FrameToView, box: CGRect, circle: FieldCircle?
    ) -> GuideScreenGeometry? {
        let middle = CGPoint(x: box.midX, y: box.midY)
        let probe = probePixels
        let origin = mapper.viewPoint(of: middle)
        guard
            let axes = GuideScreenAxes(
                origin: origin,
                xUnit: mapper.viewPoint(of: CGPoint(x: middle.x + probe, y: middle.y)),
                yUnit: mapper.viewPoint(of: CGPoint(x: middle.x, y: middle.y + probe)),
                framePixels: probe)
        else { return nil }
        let scale = mapper.scale(at: middle, probe: probe)
        let side = Double(min(box.width, box.height)) * scale
        guard side > 0 else { return nil }
        let radius = circle.map { mapper.viewRadius(of: $0) } ?? side / 2
        return GuideScreenGeometry(
            axes: axes, centre: origin, pointsPerField: side, fieldRadius: radius)
    }
}

struct LiveFieldCard: View {
    var model: ScanEngine
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
