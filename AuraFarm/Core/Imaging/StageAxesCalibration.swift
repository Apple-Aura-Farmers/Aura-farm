import CoreGraphics
import Foundation

/// The numbers `StageAxesCalibration` decides with. Data, not logic. All PLACEHOLDER, from
/// Test 4 (soil): the one-knob runs were straight to about 0.03 field.
struct StageAxesThresholds {
    /// A run must cover this much, in fields, before its direction is fitted.
    var minTravelFields: Double = 2.0
    /// The perpendicular RMS of the run from its fitted line, in fields. Test 4's one-knob runs
    /// had about 0.03; a run with both knobs turned is far above this.
    var maxStraightnessRMSFields: Double = 0.08
    /// Movement past this from where the view rested starts a run, in fields.
    var startMovingFields: Double = 0.15
    /// The two axes must be this far from parallel: the angle between them within this range.
    /// Test 4 had about 1.6 degrees of difference between the two knobs' tilts.
    var minAxisAngleDegrees: Double = 75
    var maxAxisAngleDegrees: Double = 105
    /// Not tracking for this long in a row shows "Nothing to follow here". PLACEHOLDER: the 16
    /// Nov 2026 soil run sat at 0.30 field for 38 s on a sparse patch with no word on screen.
    var noTrackSeconds: Double = 1.0
    /// Rejection and failure messages stay at least this long, by the readings' times, and the
    /// bar does not fill while one shows. PLACEHOLDER: the failure used to flash for 0.1 s.
    var messageHoldSeconds: Double = 2.0
    /// When X is accepted, "X done ✓ Stop turning" shows this long and no reading counts, so the
    /// helper can stop turning X before the Y run starts. PLACEHOLDER: the user asked for about
    /// half a second.
    var betweenAxesSeconds: Double = 0.5
}

/// How the stage's two knobs move the picture, measured, so the picture and the guide can be
/// shown straight: a column then needs only the Y knob and a step right only the X knob.
struct StageAxes: Equatable {
    /// Unit vectors, in the guide's screen-field axes at the time of the measurement, along
    /// which the X knob and the Y knob move the view. Each sign is the one nearest screen +x
    /// and screen +y.
    var xDirection: CGPoint
    var yDirection: CGPoint
    /// The angle of `xDirection` from screen +x, in degrees (positive turns toward +y).
    var tiltDegrees: Double
    /// 90 minus the angle between the two axes, in degrees.
    var skewDegrees: Double
    /// A linear map (no translation) that takes `xDirection` to the +x axis and `yDirection`
    /// to the +y axis, with a positive determinant of 1 so the mean length is kept. For a
    /// vector `(x, y)` it gives `(a*x + c*y, b*x + d*y)`, `CGAffineTransform`'s convention.
    var straightening: CGAffineTransform

    static let identity = StageAxes(
        xDirection: CGPoint(x: 1, y: 0), yDirection: CGPoint(x: 0, y: 1), tiltDegrees: 0,
        skewDegrees: 0, straightening: .identity)

    /// nil when the axes are parallel (no map exists).
    init?(xDirection: CGPoint, yDirection: CGPoint) {
        let determinant =
            Double(xDirection.x * yDirection.y) - Double(yDirection.x * xDirection.y)
        guard determinant > 1e-6 else { return nil }
        self.xDirection = xDirection
        self.yDirection = yDirection
        tiltDegrees = atan2(Double(xDirection.y), Double(xDirection.x)) * 180 / .pi
        let cosine = Double(xDirection.x * yDirection.x + xDirection.y * yDirection.y)
        skewDegrees = 90 - acos(min(max(cosine, -1), 1)) * 180 / .pi
        // The inverse of [xDirection yDirection], scaled by 1 / sqrt(det) so its determinant is 1.
        let scale = 1 / determinant.squareRoot()
        straightening = CGAffineTransform(
            a: Double(yDirection.y) * scale, b: -Double(xDirection.y) * scale,
            c: -Double(yDirection.x) * scale, d: Double(xDirection.x) * scale, tx: 0, ty: 0)
    }

    private init(
        xDirection: CGPoint, yDirection: CGPoint, tiltDegrees: Double, skewDegrees: Double,
        straightening: CGAffineTransform
    ) {
        self.xDirection = xDirection
        self.yDirection = yDirection
        self.tiltDegrees = tiltDegrees
        self.skewDegrees = skewDegrees
        self.straightening = straightening
    }
}

enum StageAxesStep: Equatable {
    case waitX, waitY, done
    case failed(String)

    /// A short word for the CSV.
    var csvName: String {
        switch self {
        case .waitX: "wait_x"
        case .waitY: "wait_y"
        case .done: "done"
        case .failed: "failed"
        }
    }
}

/// What the stage step shows after one reading.
struct StageAxesProgress: Equatable {
    var step: StageAxesStep
    /// Fields travelled on the current axis so far.
    var travelFields: Double
    var message: String
    /// A second line under the message (the particles hint on the first knob); nil otherwise.
    var hint: String? = nil
    /// Tracking has been off for `noTrackSeconds`: the message says there is nothing to follow.
    var nothingToFollow = false
    /// A rejection or failure message is being held.
    var isHeld = false
    /// The "X done ✓ Stop turning" pause is showing, with the bar full.
    var isPause = false
}

/// Measures the stage's X and Y axes from the position while the helper turns one knob at a
/// time, about `minTravelFields` each. Only readings with tracking count; others are ignored,
/// not added. A run that is not a straight line (both knobs turned) is refused and that axis
/// starts again from where the view is.
struct StageAxesCalibration {
    var thresholds: StageAxesThresholds

    private(set) var result: StageAxes?
    private var step = StageAxesStep.waitX
    private var rest: CGPoint?
    private var points: [CGPoint] = []
    private var xDirection: CGPoint?
    private var rejected = false
    private var travel = 0.0
    private var noTrackSince: Double?
    private var noTrackFor = 0.0
    private var lastSeconds = 0.0
    private var heldUntil: Double?
    private var heldMessage: String?
    private var heldIsPause = false

    init(thresholds: StageAxesThresholds = StageAxesThresholds()) {
        self.thresholds = thresholds
    }

    static let waitXMessage = "Turn only the X knob (left-right) about 2 fields, either way"
    static let waitYMessage = "Now turn only the Y knob (up-down) about 2 fields"
    static let rejectedMessage = "Keep to one knob. Try again"
    static let failedMessage = "Axes don't look right. Redo"
    static let xDoneMessage = "X done ✓ Stop turning"
    static let particlesHint = "Start on a patch with plenty of particles"
    static let nothingToFollowMessage =
        "Nothing to follow here. Turn back, or move to a patch with more particles"

    /// - Parameters:
    ///   - position: where the view is, in fields, in the guide's screen axes.
    ///   - seconds: the reading's time; the fit does not depend on it.
    mutating func update(
        position: CGPoint, tracking: TrackingState, seconds: Double
    ) -> StageAxesProgress {
        lastSeconds = seconds
        if tracking == .tracking {
            noTrackSince = nil
            noTrackFor = 0
        } else {
            noTrackSince = noTrackSince ?? seconds
            noTrackFor = seconds - (noTrackSince ?? seconds)
        }
        if let until = heldUntil {
            if seconds < until - 1e-9 {
                // A message is showing: readings are not added, so the run starts afresh after it.
                rest = nil
                points = []
                travel = 0
                return progress()
            }
            heldUntil = nil
            heldMessage = nil
            heldIsPause = false
            rejected = false
        }
        if case .failed = step { step = .waitX }
        guard step != .done, tracking == .tracking else { return progress() }

        let start = rest ?? position
        rest = start
        let moved = Self.distance(position, start)
        if points.isEmpty, moved < thresholds.startMovingFields { return progress() }
        if points.isEmpty { points = [start] }
        points.append(position)
        travel = points.map { Self.distance($0, start) }.max() ?? 0
        guard travel >= thresholds.minTravelFields else { return progress() }

        guard let line = Self.fit(points), line.rms <= thresholds.maxStraightnessRMSFields else {
            // Not one knob: this axis starts again from here.
            return hold(Self.rejectedMessage, at: position, seconds)
        }
        rejected = false
        return accept(line.direction)
    }

    /// This axis starts again, and `message` stays for `messageHoldSeconds`.
    private mutating func hold(
        _ message: String, at position: CGPoint, _ seconds: Double
    ) -> StageAxesProgress {
        rest = position
        points = []
        travel = 0
        rejected = true
        heldIsPause = false
        heldMessage = message
        heldUntil = seconds + thresholds.messageHoldSeconds
        return progress()
    }

    mutating func reset() {
        self = StageAxesCalibration(thresholds: thresholds)
    }

    private mutating func accept(_ direction: CGPoint) -> StageAxesProgress {
        rest = nil
        points = []
        let travelled = travel
        travel = 0
        if step == .waitX {
            xDirection = Self.signed(direction, toward: CGPoint(x: 1, y: 0))
            step = .waitY
            // A short pause with the bar full, so the helper can stop turning X; no reading
            // counts, and the Y run starts from the first tracked position after it.
            heldMessage = Self.xDoneMessage
            heldIsPause = true
            heldUntil = lastSeconds + thresholds.betweenAxesSeconds
            return progress(travelled)
        }
        let y = Self.signed(direction, toward: CGPoint(x: 0, y: 1))
        guard let x = xDirection, let axes = StageAxes(xDirection: x, yDirection: y) else {
            return restart(travelled)
        }
        let angle = acos(min(max(Double(x.x * y.x + x.y * y.y), -1), 1)) * 180 / .pi
        guard angle >= thresholds.minAxisAngleDegrees, angle <= thresholds.maxAxisAngleDegrees
        else { return restart(travelled) }
        result = axes
        step = .done
        return progress(travelled)
    }

    private mutating func restart(_ travelled: Double) -> StageAxesProgress {
        xDirection = nil
        // Shown for `messageHoldSeconds`; then it starts again from the X axis.
        step = .failed(Self.failedMessage)
        heldMessage = Self.failedMessage
        heldIsPause = false
        heldUntil = lastSeconds + thresholds.messageHoldSeconds
        return progress(travelled)
    }

    private func progress(_ travelled: Double? = nil) -> StageAxesProgress {
        var shown = base(travelled)
        let waiting = shown.step == .waitX || shown.step == .waitY
        if let heldMessage {
            shown.message = heldMessage
            if heldIsPause {
                shown.isPause = true
                shown.travelFields = thresholds.minTravelFields
            } else {
                shown.isHeld = true
                shown.travelFields = 0
            }
        } else if waiting, noTrackFor >= thresholds.noTrackSeconds - 1e-9 {
            shown.message = Self.nothingToFollowMessage
            shown.nothingToFollow = true
        } else if shown.step == .waitX, shown.travelFields == 0, !rejected {
            shown.hint = Self.particlesHint
        }
        return shown
    }

    private func base(_ travelled: Double?) -> StageAxesProgress {
        let shown = travelled ?? travel
        switch step {
        case .waitX:
            return StageAxesProgress(
                step: step, travelFields: shown,
                message: rejected ? Self.rejectedMessage : Self.waitXMessage)
        case .waitY:
            return StageAxesProgress(
                step: step, travelFields: shown,
                message: rejected ? Self.rejectedMessage : Self.waitYMessage)
        case .done:
            let tilt = result.map { String(format: "%.1f", $0.tiltDegrees) } ?? "0"
            return StageAxesProgress(
                step: step, travelFields: shown, message: "Stage straightened ✓ (tilt \(tilt)°)")
        case .failed(let reason):
            return StageAxesProgress(step: step, travelFields: shown, message: reason)
        }
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(Double(a.x - b.x), Double(a.y - b.y))
    }

    private static func signed(_ direction: CGPoint, toward target: CGPoint) -> CGPoint {
        let dot = direction.x * target.x + direction.y * target.y
        return dot < 0 ? CGPoint(x: -direction.x, y: -direction.y) : direction
    }

    /// The principal axis of the points (total least squares) and the perpendicular RMS from
    /// it. nil for no spread at all.
    private static func fit(_ points: [CGPoint]) -> (direction: CGPoint, rms: Double)? {
        guard points.count >= 2 else { return nil }
        let count = Double(points.count)
        let meanX = points.reduce(0) { $0 + Double($1.x) } / count
        let meanY = points.reduce(0) { $0 + Double($1.y) } / count
        var sxx = 0.0
        var syy = 0.0
        var sxy = 0.0
        for point in points {
            let dx = Double(point.x) - meanX
            let dy = Double(point.y) - meanY
            sxx += dx * dx
            syy += dy * dy
            sxy += dx * dy
        }
        sxx /= count
        syy /= count
        sxy /= count
        // The larger eigenvalue's eigenvector, and the smaller eigenvalue: the variance across.
        let half = (sxx + syy) / 2
        let spread = (((sxx - syy) / 2) * ((sxx - syy) / 2) + sxy * sxy).squareRoot()
        let angle = 0.5 * atan2(2 * sxy, sxx - syy)
        guard half + spread > 1e-12 else { return nil }
        return (CGPoint(x: cos(angle), y: sin(angle)), max(half - spread, 0).squareRoot())
    }
}
