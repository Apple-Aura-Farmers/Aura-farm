import CoreGraphics
import Foundation

/// The numbers `SpotAlignment` decides with. Data, not logic. All PLACEHOLDER: not
/// calibrated.
struct SpotAlignmentThresholds {
    /// How close to the target counts as on it, in fields.
    var alignToleranceFields: Double = 0.15
    /// How long to hold still on the target before it is captured. Stop settling time was not
    /// measured.
    var holdSeconds: Double = 1.0
    /// Beyond this the target is "far away" and the UI pins the cross to the edge.
    var farAwayFields: Double = 1.5
    /// Passed the target along the travel direction by more than this: too far.
    var overshootFields: Double = 0.3
    /// The distance to the target grew this much above the least seen, on the near side: the
    /// other way.
    var wrongWayFields: Double = 0.3
    /// The same as `MovementIndicatorThresholds.tooFastSpeedFraction`.
    var tooFastSpeedFraction: Double = 0.18
    /// Blurry readings in a row before asking for a refocus.
    var readingsForRefocus: Int = 3
}

/// Judges one target against the readings: how far, which way, whether the helper is holding
/// still on it.
///
/// Priority: refocus > slow down > too far / other way > holding / captured / aligned >
/// far away / move. Positions are in fields, in screen axes.
struct SpotAlignment {
    var thresholds: SpotAlignmentThresholds

    private(set) var target: CGPoint?
    /// The distance to the target at the last reading, in fields.
    private(set) var distance = Double.infinity
    private var direction = CGPoint.zero
    private var holds = true
    private var leastDistance = Double.infinity
    private var holdStartedAt: Double?
    private var hasCaptured = false
    private var blurryStreak = 0

    init(thresholds: SpotAlignmentThresholds = SpotAlignmentThresholds()) {
        self.thresholds = thresholds
    }

    /// Whether the current target is one to hold still on and capture.
    var holdsTarget: Bool { holds }

    /// Whether the last reading was within the tolerance of the target.
    var isAtTarget: Bool { distance <= thresholds.alignToleranceFields }

    /// Aims at `target`, recording the travel direction (start to target), and starts the
    /// least distance and the hold timer afresh.
    /// - Parameter holds: false for a target to pass through; it is never captured.
    mutating func setTarget(_ target: CGPoint, from start: CGPoint, holds: Bool = true) {
        self.target = target
        self.holds = holds
        let dx = Double(target.x - start.x)
        let dy = Double(target.y - start.y)
        let length = hypot(dx, dy)
        direction = length > 1e-9 ? CGPoint(x: dx / length, y: dy / length) : .zero
        leastDistance = .infinity
        distance = .infinity
        holdStartedAt = nil
        hasCaptured = false
    }

    mutating func clearTarget() {
        target = nil
        distance = .infinity
        holdStartedAt = nil
    }

    /// Refocus or slow down, when either applies. Also keeps the blur streak, so call it on
    /// every reading.
    mutating func warning(_ reading: GuideReading) -> GuideInstruction? {
        blurryStreak = reading.viewClass == .blurry ? blurryStreak + 1 : 0
        if blurryStreak >= thresholds.readingsForRefocus { return .refocus }
        if reading.speedFraction >= thresholds.tooFastSpeedFraction || reading.tracking == .lost {
            return .slowDown
        }
        return nil
    }

    mutating func update(_ reading: GuideReading) -> GuideInstruction {
        if let warning = warning(reading) {
            holdStartedAt = nil
            return warning
        }
        guard let target else { return .aligned }

        let dx = Double(target.x - reading.position.x)
        let dy = Double(target.y - reading.position.y)
        let remaining = hypot(dx, dy)
        distance = remaining
        let grew = remaining - leastDistance
        leastDistance = min(leastDistance, remaining)
        if hasCaptured { return .aligned }

        // Positive: the view has gone past the target along the way it was travelling.
        let along = -(dx * Double(direction.x) + dy * Double(direction.y))
        if along > thresholds.overshootFields {
            holdStartedAt = nil
            return .tooFar
        }

        if remaining <= thresholds.alignToleranceFields {
            guard holds else { return .aligned }
            guard reading.isStill else {
                holdStartedAt = nil
                return .aligned
            }
            let started = holdStartedAt ?? reading.seconds
            holdStartedAt = started
            let progress = (reading.seconds - started) / max(thresholds.holdSeconds, 1e-6)
            if progress >= 1 {
                hasCaptured = true
                return .captured
            }
            return .holding(progress: max(progress, 0))
        }

        holdStartedAt = nil
        if along <= 0, grew > thresholds.wrongWayFields { return .otherWay }
        if remaining >= thresholds.farAwayFields {
            return .farAway(direction: CGPoint(x: dx / remaining, y: dy / remaining))
        }
        return .move(toward: CGPoint(x: dx, y: dy))
    }

    mutating func reset() {
        self = SpotAlignment(thresholds: thresholds)
    }
}
