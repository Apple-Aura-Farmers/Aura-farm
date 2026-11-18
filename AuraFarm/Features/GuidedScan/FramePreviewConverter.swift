import AVFoundation
import CoreGraphics

/// Turns camera-frame pixels into points on the live preview, and back, using the preview
/// layer's own conversion. The layer knows how the frame is rotated, mirrored and cropped to
/// fill the view (aspect fill), which a hand-written mapping can only guess.
///
/// A frame rectangle is divided by the frame's size to give a metadata-output rectangle:
/// `{0, 0}` is the top left and `{1, 1}` the bottom right of the UNROTATED picture, which is
/// how the frame's top-down pixels are laid out.
///
/// `display` is the transform the lab applies to the picture to centre the field (see
/// `fitTransform`): the layer's own coordinates are mapped through it, so every mark is
/// drawn in the DISPLAYED space and stays on the picture. The identity shows the picture as
/// the layer lays it out.
struct FramePreviewConverter {
    let layer: AVCaptureVideoPreviewLayer
    let frameSize: CGSize
    let display: CGAffineTransform

    /// nil until there is a layer and a frame to convert for.
    init?(
        layer: AVCaptureVideoPreviewLayer?, frameSize: CGSize,
        display: CGAffineTransform = .identity
    ) {
        guard let layer, frameSize.width > 0, frameSize.height > 0 else { return nil }
        self.layer = layer
        self.frameSize = frameSize
        self.display = display
    }

    /// The rectangle in the layer's own space (before `display`), for a rectangle in frame
    /// pixels.
    func layerRect(of rect: CGRect) -> CGRect {
        layer.layerRectConverted(
            fromMetadataOutputRect: CGRect(
                x: rect.minX / frameSize.width, y: rect.minY / frameSize.height,
                width: rect.width / frameSize.width, height: rect.height / frameSize.height))
    }

    /// The rectangle in the displayed space, for a rectangle in frame pixels. Under a
    /// rotation this is the bounding box of the turned rectangle; use `viewPolygon` for its
    /// outline.
    func viewRect(of rect: CGRect) -> CGRect {
        layerRect(of: rect).applying(display)
    }

    /// The scale and offset that show `rect` (a rectangle in the layer's own coordinates)
    /// centred in a view of `viewSize`, as large as fits (aspect fit), clipped to the view.
    /// `rect` is kept centred on its own middle but trimmed to what the view actually shows
    /// of the layer, because the layer draws nothing outside its bounds. The identity when
    /// there is nothing sensible to show.
    static func fitTransform(of rect: CGRect, in viewSize: CGSize) -> CGAffineTransform {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let halfWidth = min(rect.width / 2, centre.x, viewSize.width - centre.x)
        let halfHeight = min(rect.height / 2, centre.y, viewSize.height - centre.y)
        guard halfWidth >= 8, halfHeight >= 8, viewSize.width > 0, viewSize.height > 0 else {
            return .identity
        }
        let scale = min(viewSize.width / (halfWidth * 2), viewSize.height / (halfHeight * 2))
        return CGAffineTransform(translationX: viewSize.width / 2, y: viewSize.height / 2)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -centre.x, y: -centre.y)
    }

    /// How a confirmed field is shown in a SQUARE preview of `viewSize`: the circle's
    /// bounding square (`FieldCentring`) fills the view, the circle centred, and the picture
    /// straightened by `stage` about the circle's centre. The identity while the field is
    /// not learned and confirmed (still learning, waiting for review or being adjusted: the
    /// uncropped picture, which the review's circle is mapped through).
    ///
    /// The preview layer must use `.resizeAspect`: with aspect fill a circle away from the
    /// middle of the frame has part of its square outside what the layer draws.
    static func displayTransform(
        for field: SlideMovementInfo.Field, layer: AVCaptureVideoPreviewLayer?,
        viewSize: CGSize, stage: StageAxes = .identity
    ) -> CGAffineTransform {
        guard !field.awaitingReview, let mask = field.state?.mask,
            let circle = FieldCircle(fitting: mask),
            let plain = FramePreviewConverter(layer: layer, frameSize: field.frameSize)
        else { return .identity }
        let crop = FieldCentring.cropRect(for: circle, frameSize: field.frameSize)
        return displayTransform(
            crop: plain.layerRect(of: crop),
            centre: plain.layerRect(of: CGRect(origin: circle.centre, size: .zero)).origin,
            straightening: stage.straightening, viewSize: viewSize)
    }

    /// The pure part of `displayTransform(for:layer:viewSize:stage:)`: `straightening`
    /// (a linear map) about `centre`, then the fit of `crop`, both in the layer's own space.
    /// The centre of the field ends at the middle of the view.
    static func displayTransform(
        crop: CGRect, centre: CGPoint, straightening: CGAffineTransform, viewSize: CGSize
    ) -> CGAffineTransform {
        let about = CGAffineTransform(
            a: straightening.a, b: straightening.b, c: straightening.c, d: straightening.d,
            tx: centre.x - (straightening.a * centre.x + straightening.c * centre.y),
            ty: centre.y - (straightening.b * centre.x + straightening.d * centre.y))
        return about.concatenating(fitTransform(of: crop, in: viewSize))
    }

    func viewPoint(of point: CGPoint) -> CGPoint {
        viewRect(of: CGRect(origin: point, size: .zero)).origin
    }

    /// The frame pixel under a point of the displayed space.
    func framePoint(fromView point: CGPoint) -> CGPoint {
        let normalised = layer.metadataOutputRectConverted(
            fromLayerRect: CGRect(origin: point.applying(display.inverted()), size: .zero))
        return CGPoint(
            x: normalised.origin.x * frameSize.width, y: normalised.origin.y * frameSize.height)
    }
}

extension FrameToView {
    /// Points per frame pixel at `point`: the mean length of two probe vectors (`probe` px
    /// along frame x and along frame y). The length of a probe is right under a rotation or
    /// a shear, where the bounding box of a rectangle grows (about 1.16 times at 10
    /// degrees).
    func scale(at point: CGPoint, probe: Double = 100) -> Double {
        let origin = viewPoint(of: point)
        let along = viewPoint(of: CGPoint(x: point.x + probe, y: point.y))
        let down = viewPoint(of: CGPoint(x: point.x, y: point.y + probe))
        let x = hypot(Double(along.x - origin.x), Double(along.y - origin.y))
        let y = hypot(Double(down.x - origin.x), Double(down.y - origin.y))
        return (x + y) / 2 / probe
    }

    /// A circle's radius on the preview, in points.
    func viewRadius(of circle: FieldCircle) -> Double {
        circle.radius * scale(at: circle.centre)
    }

    /// The four corners of a frame rectangle on the preview, in order: turned with the
    /// picture, unlike `viewRect`'s bounding box.
    func viewPolygon(of rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
        ].map { viewPoint(of: $0) }
    }
}
