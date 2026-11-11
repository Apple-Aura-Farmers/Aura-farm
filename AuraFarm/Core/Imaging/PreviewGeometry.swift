import CoreGraphics
import Foundation

/// Where a rectangle of the camera frame lands on a preview that shows the frame through a
/// `ScreenMapping` and fills its view (aspect fill).
///
/// Rough by design: it assumes the preview is turned the way the mapping says, which is only
/// as right as the mapping the team picked.
enum PreviewGeometry {
    /// The bounding rectangle, in view points, of `rect` (frame pixels, top-down).
    static func rect(
        of rect: CGRect, frameSize: CGSize, viewSize: CGSize, mapping: ScreenMapping,
        mirrored: Bool
    ) -> CGRect {
        let turnsAxes = mapping == .rotateRight || mapping == .rotateLeft
        let shown = turnsAxes ? CGSize(width: frameSize.height, height: frameSize.width) : frameSize
        guard shown.width > 0, shown.height > 0 else { return .zero }
        let scale = max(viewSize.width / shown.width, viewSize.height / shown.height)
        let frameCentre = CGPoint(x: frameSize.width / 2, y: frameSize.height / 2)
        let viewCentre = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)

        let corners = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY),
        ].map { corner -> CGPoint in
            let moved = mapping.onScreen(
                CGPoint(x: corner.x - frameCentre.x, y: corner.y - frameCentre.y),
                mirrored: mirrored)
            return CGPoint(x: viewCentre.x + moved.x * scale, y: viewCentre.y + moved.y * scale)
        }
        let xs = corners.map(\.x)
        let ys = corners.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max()
        else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The transform taking frame pixels to view points, the same placement `rect(of:...)`
    /// uses. Lets a whole image of the frame be drawn rotated.
    static func transform(
        frameSize: CGSize, viewSize: CGSize, mapping: ScreenMapping, mirrored: Bool
    ) -> CGAffineTransform {
        let turnsAxes = mapping == .rotateRight || mapping == .rotateLeft
        let shown = turnsAxes ? CGSize(width: frameSize.height, height: frameSize.width) : frameSize
        guard shown.width > 0, shown.height > 0 else { return .identity }
        let scale = max(viewSize.width / shown.width, viewSize.height / shown.height)
        let across = mapping.onScreen(CGPoint(x: 1, y: 0), mirrored: mirrored)
        let down = mapping.onScreen(CGPoint(x: 0, y: 1), mirrored: mirrored)
        let linear = CGAffineTransform(
            a: across.x * scale, b: across.y * scale, c: down.x * scale, d: down.y * scale,
            tx: 0, ty: 0)
        let centre = CGPoint(x: frameSize.width / 2, y: frameSize.height / 2).applying(linear)
        return linear.concatenating(
            CGAffineTransform(
                translationX: viewSize.width / 2 - centre.x,
                y: viewSize.height / 2 - centre.y))
    }
}
