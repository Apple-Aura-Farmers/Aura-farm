import CoreGraphics

/// How the picture's shift between frames is read by the tally.
enum PictureShift {
    /// The picture moved by the opposite of the registered shift: the shift is how far the CONTENT
    /// has to move to line up, so a thing that stayed put on the slide has gone the other way.
    /// Measured as well as reasoned: on a 23 second clip, this way round counted 125 where the
    /// other way counted 225 and ignoring the shift counted 160. nil (no shift measured) is no
    /// movement.
    static func pictureMoved(registered shift: CGPoint?) -> CGPoint {
        guard let shift else { return .zero }
        return CGPoint(x: -shift.x, y: -shift.y)
    }
}
