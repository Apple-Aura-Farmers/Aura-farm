import CoreGraphics
import Foundation

/// Drops boxes that are the model answering about the eyepiece disc or the thick sample band
/// rather than finding an organism. Used on the live-count path only; the capture screen keeps
/// `OrganismDetector.largestBoxShare` and nothing else.
///
/// Measured by the reviewer on 103 saved 1280 x 720 frames, V2: squashing the whole frame gave
/// 17 frames with ONE box around the bright disc (about 0.47 x 0.77 of the frame, labelled
/// Volvox or Nematode, the same place every frame). Cropped to the circle's square the disc boxes
/// went, leaving small boxes (0.07 to 0.16 of the crop, area under 0.03) and a few large ones over
/// the sample band at the cover-slip edge (0.49 x 0.63 and 0.73 x 0.91 of the crop, scores up to
/// 0.82), which are false.
struct DetectionGuards: Equatable {
    /// With a crop: a box covering more than this share of the crop's AREA is dropped. PLACEHOLDER;
    /// the band boxes covered 0.31 and 0.66, the real-looking ones under 0.03. At 0.5 the 0.31 box
    /// survives; lower it if the band still produces counts.
    var maxBoxShareOfInput = 0.5
    /// Without a crop, when the field circle is known: a box whose IoU with the circle's bounding
    /// square is at least this is the disc. PLACEHOLDER; the disc box was about 0.8.
    var discOverlapIoU = 0.5

    enum Drop: Equatable {
        case disc, big
    }

    /// Why `box` is dropped, or nil to keep it.
    /// - Parameters:
    ///   - box: frame pixels, origin top left.
    ///   - crop: the square the model saw, frame pixels, or nil when it saw the whole frame.
    ///   - circle: the field circle in frame pixels, when known.
    func drop(box: CGRect, crop: CGRect?, circle: FieldCircle?) -> Drop? {
        if let crop {
            let share = Double(box.width * box.height) / max(Double(crop.width * crop.height), 1)
            return share > maxBoxShareOfInput ? .big : nil
        }
        if let circle {
            let square = CGRect(
                x: circle.centre.x - circle.radius, y: circle.centre.y - circle.radius,
                width: circle.radius * 2, height: circle.radius * 2)
            return Self.iou(box, square) >= discOverlapIoU ? .disc : nil
        }
        return nil
    }

    static func iou(_ one: CGRect, _ other: CGRect) -> Double {
        let overlap = one.intersection(other)
        guard !overlap.isNull else { return 0 }
        let shared = Double(overlap.width * overlap.height)
        let union = Double(one.width * one.height + other.width * other.height) - shared
        return union > 0 ? shared / union : 0
    }
}
