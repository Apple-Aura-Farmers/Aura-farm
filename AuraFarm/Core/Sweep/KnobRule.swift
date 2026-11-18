import CoreGraphics
import Foundation

/// The numbers `KnobRule` decides with. Data, not logic.
struct KnobRuleThresholds: Equatable {
    /// An arrow more than this many degrees off both screen axes also asks for a little of the
    /// other knob. PLACEHOLDER: chosen by eye; the straightened picture keeps real arrows near an
    /// axis, so this only fires on a true diagonal.
    var diagonalDegrees: Double = 30
}

/// The microscope's rule from arrow to knob, as data. It maps the direction the guide's arrow
/// points on the DISPLAYED picture (rotated 90 degrees left and straightened, as drawn) straight
/// to a knob and a way to turn it. There is no inversion: the arrow says where the picture has
/// to go, and this says which knob does that on this microscope.
///
/// The defaults are the user's rule: the X knob is the bottom knob, the Y knob the top one;
/// arrow left = bottom towards you, right = bottom away, up = top towards you, down = top away.
/// The lab's switches (`swapsKnobs`, `reversesX`, `reversesY`) are for other microscopes.
struct KnobRule: Equatable {
    enum Knob: String, Equatable { case bottom, top }
    enum Way: String, Equatable { case towardsYou, awayFromYou }

    /// What to turn: the main knob and the way, and whether a little of the other knob helps.
    struct Words: Equatable {
        var knob: Knob
        var way: Way
        var alsoOtherKnob: Bool

        /// "Bottom knob towards you", or with the diagonal addition.
        var text: String {
            let base = "\(knob == .bottom ? "Bottom" : "Top") knob \(Self.wayText(way))"
            guard alsoOtherKnob else { return base }
            return "\(base) and a little of the \(knob == .bottom ? "top" : "bottom") knob"
        }

        /// `text` with a lower-case first letter, to follow "Back a little: ".
        var phrase: String { text.prefix(1).lowercased() + text.dropFirst() }

        /// The turning direction alone, which the drawing shows as a curved arrow.
        private static func wayText(_ way: Way) -> String {
            way == .towardsYou ? "towards you" : "away from you"
        }
    }

    /// Which knob moves the picture left and right. The rule has the bottom one.
    var xKnob = Knob.bottom
    /// Flips the way for the left-right knob / the up-down knob.
    var reversesX = false
    var reversesY = false
    var thresholds = KnobRuleThresholds()

    /// The words for an arrow pointing `direction` on the displayed picture (screen axes, y
    /// down, exactly as the overlay draws it). nil for no direction.
    func words(forArrowDirection direction: CGPoint) -> Words? {
        let x = Double(direction.x)
        let y = Double(direction.y)
        guard hypot(x, y) > 1e-9 else { return nil }

        let horizontal = abs(x) >= abs(y)
        // Left and up are "towards you"; reversing flips it.
        let towards =
            horizontal ? (x < 0) != reversesX : (y < 0) != reversesY
        let xIsBottom = xKnob == .bottom
        let knob: Knob = horizontal == xIsBottom ? .bottom : .top

        let minor = min(abs(x), abs(y))
        let major = max(abs(x), abs(y))
        let off = atan2(minor, major) * 180 / .pi
        return Words(
            knob: knob, way: towards ? .towardsYou : .awayFromYou,
            alsoOtherKnob: off > thresholds.diagonalDegrees)
    }

    /// True when the measured X-knob axis is closer to screen-vertical than horizontal: the rule
    /// ("X knob moves the picture left and right") would then be wrong for this microscope.
    static func xAxisIsVertical(_ xDirection: CGPoint) -> Bool {
        abs(xDirection.y) > abs(xDirection.x)
    }
}

extension GuideOverlayModel {
    /// The direction the arrow (or the cross, from the centre) points, in screen axes exactly as
    /// drawn. nil when nothing points anywhere.
    var arrowDirection: CGPoint? {
        switch mark {
        case .cross(let point, _): CGPoint(x: point.x - centre.x, y: point.y - centre.y)
        case .pinnedArrow(_, let angle, _, _): CGPoint(x: cos(angle), y: sin(angle))
        case .none: nil
        }
    }
}
