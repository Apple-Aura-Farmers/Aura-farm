import CoreGraphics
import Foundation

/// How the camera frame's axes (x right, y down) map onto the screen, for drawing a movement
/// the way the person sees it. The lab lets the team pick the one where a dot moves the way
/// the view really moves; the guided sweep will then need it fixed.
enum ScreenMapping: String, CaseIterable, Identifiable {
    case asIs
    case rotateRight
    case rotateLeft
    case rotate180

    var id: String { rawValue }

    var title: String {
        switch self {
        case .asIs: "As is"
        case .rotateRight: "Rotate 90° right"
        case .rotateLeft: "Rotate 90° left"
        case .rotate180: "Rotate 180°"
        }
    }

    /// A vector in frame axes, as a vector on screen (x right, y down). Rotation first, then
    /// the mirror, which flips the screen's horizontal.
    func onScreen(_ vector: CGPoint, mirrored: Bool) -> CGPoint {
        let rotated: CGPoint
        switch self {
        case .asIs: rotated = vector
        case .rotateRight: rotated = CGPoint(x: -vector.y, y: vector.x)
        case .rotateLeft: rotated = CGPoint(x: vector.y, y: -vector.x)
        case .rotate180: rotated = CGPoint(x: -vector.x, y: -vector.y)
        }
        return mirrored ? CGPoint(x: -rotated.x, y: rotated.y) : rotated
    }
}
