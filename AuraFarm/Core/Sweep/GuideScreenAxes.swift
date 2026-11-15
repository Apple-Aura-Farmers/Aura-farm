import CoreGraphics
import Foundation

/// How a vector in camera-frame pixels appears on screen, measured from the live preview
/// itself rather than chosen by hand: a 2x2 linear map, `screen = (a*x + b*y, c*x + d*y)`, for a
/// frame vector `(x, y)`. Screen is in points, x right, y down.
///
/// Sign convention: these axes show where a frame vector lands on the PREVIEW, so they map the
/// CONTENT's motion. The tracker's position is the content's displacement in frame pixels
/// (`HopOdometer`), so the VIEW's travel is its negation: `viewTravel` is these axes negated,
/// and the guide's position is `viewTravel.screenVector(position)`. A spot at view position
/// `T`, seen while the view is at `P`, appears at the box's centre on screen plus the screen
/// vector of `T - P`. That is what keeps a target cross glued to the picture as the knobs turn.
struct GuideScreenAxes: Equatable {
    var a: Double
    var b: Double
    var c: Double
    var d: Double

    /// The determinant below which the map counts as degenerate.
    private static let minimumDeterminant = 1e-9

    init(a: Double, b: Double, c: Double, d: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
    }

    /// Built from three preview points: where a frame point `P` shows on screen (`origin`),
    /// where `P + (framePixels, 0)` does (`xUnit`) and where `P + (0, framePixels)` does
    /// (`yUnit`). nil when the three points do not span a plane.
    init?(origin: CGPoint, xUnit: CGPoint, yUnit: CGPoint, framePixels: Double) {
        guard framePixels > 0 else { return nil }
        let a = Double(xUnit.x - origin.x) / framePixels
        let c = Double(xUnit.y - origin.y) / framePixels
        let b = Double(yUnit.x - origin.x) / framePixels
        let d = Double(yUnit.y - origin.y) / framePixels
        guard abs(a * d - b * c) > Self.minimumDeterminant else { return nil }
        self.init(a: a, b: b, c: c, d: d)
    }

    /// The manual fallback, matching `ScreenMapping.onScreen`. That mapping describes the
    /// view's travel, so for content axes (what `guideFields` expects) use its `viewTravel`. `pointsPerPixel` scales frame
    /// pixels to screen points (1 gives pixels).
    static func from(
        _ mapping: ScreenMapping, mirrored: Bool, pointsPerPixel: Double
    ) -> GuideScreenAxes {
        let x = mapping.onScreen(CGPoint(x: 1, y: 0), mirrored: mirrored)
        let y = mapping.onScreen(CGPoint(x: 0, y: 1), mirrored: mirrored)
        return GuideScreenAxes(
            a: Double(x.x) * pointsPerPixel, b: Double(y.x) * pointsPerPixel,
            c: Double(x.y) * pointsPerPixel, d: Double(y.y) * pointsPerPixel)
    }

    var determinant: Double { a * d - b * c }

    /// A frame vector (px) as a screen vector (points).
    func screenVector(ofFrameVector v: CGPoint) -> CGPoint {
        CGPoint(x: a * Double(v.x) + b * Double(v.y), y: c * Double(v.x) + d * Double(v.y))
    }

    /// These axes for the VIEW's travel instead of the content's: the negation. With axes
    /// measured from the preview this is what the lab's picker describes.
    var viewTravel: GuideScreenAxes { GuideScreenAxes(a: -a, b: -b, c: -c, d: -d) }

    /// The guide's position, in screen fields, for the tracker's position in frame pixels (the
    /// content's displacement, so the view's travel is its negation). The one conversion
    /// `GuideDryRun` uses; these must be the axes of the content's motion on screen.
    func guideFields(forTrackerPosition position: CGPoint, pointsPerField: Double) -> CGPoint {
        let screen = screenVector(ofFrameVector: CGPoint(x: -position.x, y: -position.y))
        return CGPoint(x: Double(screen.x) / pointsPerField, y: Double(screen.y) / pointsPerField)
    }

    /// The inverse; nil when the map is degenerate.
    func frameVector(ofScreenVector v: CGPoint) -> CGPoint? {
        let det = determinant
        guard abs(det) > Self.minimumDeterminant else { return nil }
        return CGPoint(
            x: (d * Double(v.x) - b * Double(v.y)) / det,
            y: (-c * Double(v.x) + a * Double(v.y)) / det)
    }

    /// The manual mapping these axes are nearest to, for the lab's check that the preview and
    /// the picker agree. Compared by direction, so the scale does not matter.
    func closestMapping() -> (mapping: ScreenMapping, mirrored: Bool) {
        let scale = sqrt(abs(determinant))
        let own = scale > 0 ? [a, b, c, d].map { $0 / scale } : [a, b, c, d]
        var best = (mapping: ScreenMapping.asIs, mirrored: false)
        var bestDistance = Double.infinity
        for mapping in ScreenMapping.allCases {
            for mirrored in [false, true] {
                let candidate = Self.from(mapping, mirrored: mirrored, pointsPerPixel: 1)
                let values = [candidate.a, candidate.b, candidate.c, candidate.d]
                let distance = zip(own, values).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }
                if distance < bestDistance {
                    bestDistance = distance
                    best = (mapping, mirrored)
                }
            }
        }
        return best
    }
}
