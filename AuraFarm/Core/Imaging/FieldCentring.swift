import CoreGraphics
import Foundation

/// Where to crop the camera frame so the eyepiece field fills a square picture.
///
/// The crop is the circle's bounding square, a little larger (`cropMarginFactor`), centred on the
/// circle and kept inside the frame (it shrinks, still centred, when the circle is near an edge).
/// The lab shows exactly this square, full width on screen, and everything outside the circle in
/// it dark. Phase 3b will crop saved frames with this same square, so the picture the helper sees
/// is the picture that is kept. Registration is not affected: it keeps using the learned box in
/// full-frame pixels.
enum FieldCentring {
    /// The smallest side a crop may have, in px. A crop smaller than this is no use as a
    /// picture, so the whole frame is used instead. PLACEHOLDER: not calibrated.
    static let minimumSide: CGFloat = 16

    /// The crop's side as a multiple of the circle's diameter, so the rim is not cut. PLACEHOLDER:
    /// not calibrated; 2% leaves room for the circle's slight ellipse once the picture is
    /// straightened (the two knobs' tilts differed by about 1.6 degrees in Test 4).
    static let cropMarginFactor = 1.02

    /// The square centred on `centre` of `radius` times `cropMarginFactor`, in whole pixels,
    /// top-down like the frame, kept inside the frame by shrinking it. The whole frame when
    /// that would be under `minimumSide` a side.
    static func cropRect(centre: CGPoint, radius: Double, frameSize: CGSize) -> CGRect {
        let whole = CGRect(origin: .zero, size: frameSize)
        let room = min(centre.x, frameSize.width - centre.x, centre.y, frameSize.height - centre.y)
        let half = min(CGFloat(radius * cropMarginFactor), room).rounded(.down)
        let side = half * 2
        guard side >= minimumSide else { return whole }
        // Whole pixels: the origin is the centre less half the side, rounded, and kept inside.
        let x = min(max((centre.x - half).rounded(), 0), frameSize.width - side)
        let y = min(max((centre.y - half).rounded(), 0), frameSize.height - side)
        return CGRect(x: x, y: y, width: side, height: side)
    }

    /// The crop for the field `mask` describes (its open cells fitted by a circle); nil when it
    /// has no open cells. A field the person adjusted by hand is a mask too, so this covers it.
    static func cropRect(for mask: FieldMask, frameSize: CGSize) -> CGRect? {
        FieldCircle(fitting: mask).map { cropRect(for: $0, frameSize: frameSize) }
    }

    /// The crop for a field drawn as a circle.
    static func cropRect(for circle: FieldCircle, frameSize: CGSize) -> CGRect {
        cropRect(centre: circle.centre, radius: circle.radius, frameSize: frameSize)
    }
}
