import CoreGraphics
import Foundation

/// The maths of an organism's picture: the detection box with a margin, squared, kept inside the
/// frame, and the size it is saved at. Pure.
enum OrganismCrop {
    /// Added on each side of the box, as a share of its width and height.
    static let marginShare = 0.5
    /// The longer side of the saved picture, in pixels, at most.
    static let maxSide = 384.0

    /// The square to cut from the frame (px, from the top left): the box grown by the margin on
    /// each side, squared on its centre, no bigger than the frame, shifted to lie inside it.
    static func rect(box: CGRect, frame: CGSize) -> CGRect {
        let grown = max(box.width, box.height) * (1 + 2 * marginShare)
        let side = min(grown, min(frame.width, frame.height)).rounded()
        let x = min(max((box.midX - side / 2).rounded(), 0), frame.width - side)
        let y = min(max((box.midY - side / 2).rounded(), 0), frame.height - side)
        return CGRect(x: x, y: y, width: side, height: side)
    }

    /// The saved size of a crop `side` pixels wide: shrunk to `maxSide`, never enlarged.
    static func outputSide(for side: CGFloat) -> Int {
        Int((min(1, maxSide / max(side, 1)) * side).rounded())
    }
}
