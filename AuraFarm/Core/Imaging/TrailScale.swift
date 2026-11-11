import CoreGraphics
import Foundation

/// How far the trail drawing reaches from its centre, in frames, so a long move still fits.
enum TrailScale {
    /// The least reach. PLACEHOLDER: not calibrated, chosen so a 3 frame move fills most of the box.
    static let minimumReach = 3.0

    /// The reach that fits every point (and the extra points, such as the start), as a whole
    /// number of frames so the grid lines land on frames. Never below `minimumReach`.
    static func reach(for points: [CGPoint]) -> Double {
        let furthest = points.map { max(abs(Double($0.x)), abs(Double($0.y))) }.max() ?? 0
        return max(minimumReach, furthest.rounded(.up) + 1)
    }
}
