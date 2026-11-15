import CoreGraphics
import Foundation

/// Where to crop the camera frame so the eyepiece field sits in the middle of the picture.
///
/// A field that is off centre in the frame (low and to the left, say) is centred by trimming the
/// side with more room: the crop is the largest rectangle centred on the field that still fits
/// inside the frame. The trimmed part is the red-tinted ring area. The lab uses this for its
/// display only; Phase 3b will crop saved frames with this same rectangle, so the picture the
/// helper sees is the picture that is kept. Registration is not affected: it keeps using the
/// learned box in full-frame pixels.
enum FieldCentring {
    /// The smallest side a crop may have, in px. A crop smaller than this is no use as a
    /// picture, so the whole frame is used instead. PLACEHOLDER: not calibrated.
    static let minimumSide: CGFloat = 16

    /// The largest rectangle centred on `centre` that fits inside the frame, in whole pixels,
    /// top-down like the frame. The whole frame when that would be under `minimumSide` a side.
    static func cropRect(centre: CGPoint, frameSize: CGSize) -> CGRect {
        let whole = CGRect(origin: .zero, size: frameSize)
        let halfWidth = min(centre.x, frameSize.width - centre.x).rounded(.down)
        let halfHeight = min(centre.y, frameSize.height - centre.y).rounded(.down)
        let width = halfWidth * 2
        let height = halfHeight * 2
        guard width >= minimumSide, height >= minimumSide else { return whole }
        // Whole pixels: the origin is the centre less half the side, rounded, and kept inside.
        let x = min(max((centre.x - halfWidth).rounded(), 0), frameSize.width - width)
        let y = min(max((centre.y - halfHeight).rounded(), 0), frameSize.height - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The crop for the field `mask` describes (its open cells fitted by a circle); nil when it
    /// has no open cells. A field the person adjusted by hand is a mask too, so this covers it.
    static func cropRect(for mask: FieldMask, frameSize: CGSize) -> CGRect? {
        FieldCircle(fitting: mask).map { cropRect(for: $0, frameSize: frameSize) }
    }

    /// The crop for a field drawn as a circle.
    static func cropRect(for circle: FieldCircle, frameSize: CGSize) -> CGRect {
        cropRect(centre: circle.centre, frameSize: frameSize)
    }
}
