import CoreGraphics
import Foundation

/// How sharp each half of the box is now, relative to the same patch of content in the anchor
/// frame (the last re-anchor): about 1 means as sharp as it was, well below 1 means the same
/// content is now blurred. A half is nil when the anchor does not cover enough of it.
struct HalfFocus: Equatable {
    var left: Double?
    var right: Double?
    var top: Double?
    var bottom: Double?

    func ratio(_ side: BoxHalves.Side) -> Double? {
        switch side {
        case .left: left
        case .right: right
        case .top: top
        case .bottom: bottom
        }
    }

    /// The ratios ahead of and behind a view travelling toward `direction` (frame axes).
    func aheadAndBehind(forFrameDirection direction: CGPoint) -> (ahead: Double?, behind: Double?)? {
        guard let side = BoxHalves.ahead(forFrameDirection: direction) else { return nil }
        return (ratio(side), ratio(BoxHalves.opposite(of: side)))
    }
}

/// The sharpness of the four halves of the registration box, in FRAME axes (left, right, top
/// and bottom). Sampled at `SlideTracker.statsStep`, like the box stats.
///
/// When the edge of the sample reaches the middle of the view, the half it is coming from is
/// blank and the other still has detail, which the whole box (sharpness averaged over both)
/// can miss.
struct BoxHalves: Equatable {
    var left: Double
    var right: Double
    var top: Double
    var bottom: Double

    enum Side: Equatable { case left, right, top, bottom }

    func sharpness(_ side: Side) -> Double {
        switch side {
        case .left: left
        case .right: right
        case .top: top
        case .bottom: bottom
        }
    }

    static func opposite(of side: Side) -> Side {
        switch side {
        case .left: .right
        case .right: .left
        case .top: .bottom
        case .bottom: .top
        }
    }

    /// The half that new content comes into view on, for a view travelling toward the frame
    /// direction `direction` (frame axes, x right, y down): the side whose outward direction
    /// matches it best, the dominant axis for a diagonal (x on a tie). nil for no direction.
    static func ahead(forFrameDirection direction: CGPoint) -> Side? {
        let x = Double(direction.x)
        let y = Double(direction.y)
        guard hypot(x, y) > 1e-9 else { return nil }
        if abs(x) >= abs(y) { return x >= 0 ? .right : .left }
        return y >= 0 ? .bottom : .top
    }

    /// The sharpness ahead of and behind a view travelling toward `direction`.
    func aheadAndBehind(forFrameDirection direction: CGPoint) -> (ahead: Double, behind: Double)? {
        guard let side = Self.ahead(forFrameDirection: direction) else { return nil }
        return (sharpness(side), sharpness(Self.opposite(of: side)))
    }
}
