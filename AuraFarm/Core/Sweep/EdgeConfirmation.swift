import CoreGraphics
import Foundation

/// The numbers `EdgeConfirmation` decides with. Data, not logic. All PLACEHOLDER: not
/// calibrated; calibrate from the `focus_*` and `box_sharp_*` CSV columns.
struct EdgeConfirmationThresholds {
    /// The view must have travelled at least this far along the heading in the
    /// `arriveWindowSeconds` before the candidate began: a real edge is arrived at. A blur
    /// leaves the content where it was.
    var arriveFields: Double = 0.10
    var arriveWindowSeconds: Double = 1.0
    /// The condition must hold this long, with the helper still, in a row, before the edge counts.
    /// PLACEHOLDER: 2.0 (the user's request; it was 1.0).
    /// Fps is about 10; a flick or a focus slip clears faster than this.
    var confirmSeconds: Double = 2.0
    /// The half behind must be at least this sharp relative to the same patch in the last
    /// sharp frame: it still shows the same content, just as sharp.
    var behindFocusRatioMin: Double = 0.6
    /// Both halves (or the half behind) below this, with no arrival, is blur: refocus.
    var blurFocusRatioMax: Double = 0.6
    /// The same as `MovementIndicatorThresholds.tooFastSpeedFraction`; a spike restarts the
    /// candidate.
    var tooFastSpeedFraction: Double = 0.18
    /// A half-edge candidate that began within this long before the helper reached a spot's
    /// target (or after) is not built up by the stillness of holding on that spot: holding is
    /// not resting at an edge. PLACEHOLDER: about half the capture hold (`holdSeconds`, 1 s).
    var spotHoldSeconds: Double = 0.5
}

/// What the route's raw conditions make of the current reading.
enum EdgeCandidate: Equatable {
    case none
    /// The half ahead has no detail and the half behind has.
    case halfEdge
    /// The whole box has low detail (or the tracker is paused): the overshoot fallback.
    case wholeBoxLowDetail

    /// The CSV word.
    var csvName: String {
        switch self {
        case .none: "none"
        case .halfEdge: "half_edge"
        case .wholeBoxLowDetail: "whole_box"
        }
    }
}

enum EdgeVerdict: Equatable {
    case none
    /// Still checking, 0...1.
    case checking(progress: Double)
    case confirmed
    /// The same content blurred, not new blank content: refocus.
    case blur

    /// The CSV word.
    var csvName: String {
        switch self {
        case .none: "none"
        case .checking: "checking"
        case .confirmed: "confirmed"
        case .blur: "blur"
        }
    }
}

/// Tells a real edge from an image that went soft for a moment (a knock, a flick, a focus
/// slip). A detail drop alone cannot: new blank content and the same content blurred look
/// alike in one frame. A real edge is arrived at (the view travelled toward it), the half
/// behind still shows the same sample as sharp as before, and it persists while the helper
/// rests there.
struct EdgeConfirmation {
    var thresholds: EdgeConfirmationThresholds
    /// The sharpness under which a half has no detail (`GuidedSweepThresholds`).
    var halfCut: Double

    /// The distance travelled along the heading before the candidate began, in fields.
    private(set) var arrivalFields = 0.0
    /// How long the candidate has held with the helper still, in seconds. Any reading that is
    /// not still sets it back to zero: an edge is confirmed only at rest.
    private(set) var heldSeconds = 0.0
    /// Why the last `update` said what it said, for the CSV: arrived, not_arrived, vouched,
    /// behind_blurred, speed_spike or spot_hold; empty when there is nothing to say.
    private(set) var reason = ""

    private var history: [(seconds: Double, position: CGPoint)] = []
    private var activeKind = EdgeCandidate.none
    private var activeSince: Double?
    private var firstSeen = 0.0
    private var arrived = false
    private var restartAt = -Double.infinity
    private var lastSeconds: Double?
    /// The focus ratios of the last reading with tracking: what the pause that follows hides.
    private var lastTrackedAhead: Double?
    private var lastTrackedBehind: Double?

    init(thresholds: EdgeConfirmationThresholds = EdgeConfirmationThresholds(), halfCut: Double = 120) {
        self.thresholds = thresholds
        self.halfCut = halfCut
    }

    /// - Parameters:
    ///   - heading: the direction the view is being sent (screen unit vector).
    ///   - candidate: what the route's raw conditions make of this reading.
    ///   - since: when that condition began (half-box rule) or when the low-detail stretch
    ///     began (whole box). Arrival is measured over the window before it.
    ///   - spotReachedAt: when the helper got onto the current spot's target and is holding
    ///     there, nil when not. See `EdgeConfirmationThresholds.spotHoldSeconds`.
    mutating func update(
        reading: GuideReading, heading: CGPoint?, candidate: EdgeCandidate, since: Double?,
        spotReachedAt: Double? = nil
    ) -> EdgeVerdict {
        let now = reading.seconds
        reason = ""
        defer { lastSeconds = now }
        history.append((now, reading.position))
        history.removeAll { now - $0.seconds > thresholds.arriveWindowSeconds + 3 }
        if reading.tracking == .tracking {
            lastTrackedAhead = reading.aheadFocusRatio ?? lastTrackedAhead
            lastTrackedBehind = reading.behindFocusRatio ?? lastTrackedBehind
        }

        guard candidate != .none, let since else {
            clearCandidate()
            return .none
        }
        let start = max(since, restartAt)
        if candidate != activeKind || activeSince != start {
            activeKind = candidate
            activeSince = start
            firstSeen = now
            heldSeconds = 0
            arrivalFields = Self.arrival(
                history: history, start: start, heading: heading,
                window: thresholds.arriveWindowSeconds)
            arrived = arrivalFields >= thresholds.arriveFields - 1e-6
        }
        // Not arrived at the start? The view may still travel in: look again at the last
        // `arriveWindowSeconds`, and keep the arrival once it is there.
        if !arrived {
            let latest = Self.arrival(
                history: history, start: now, heading: heading,
                window: thresholds.arriveWindowSeconds)
            arrivalFields = max(arrivalFields, latest)
            arrived = arrivalFields >= thresholds.arriveFields - 1e-6
        }
        let step = min(max(now - (lastSeconds ?? now), 0), 0.5)

        switch candidate {
        case .none:
            return .none
        case .halfEdge:
            guard let ahead = reading.aheadSharpness, let behind = reading.behindSharpness,
                ahead < halfCut, behind >= halfCut
            else {
                clearCandidate()
                return .none
            }
            // No arrival is only blur when the focus does not vouch for the content: the half
            // behind as sharp as in the last sharp frame is the same sample, so an edge that
            // the helper started at (or came to from the side) can still be checked.
            let vouched = (reading.behindFocusRatio ?? 0) >= thresholds.behindFocusRatioMin
            guard arrived || vouched else {
                reason = "not_arrived"
                return .blur
            }
            if let ratio = reading.behindFocusRatio, ratio < thresholds.blurFocusRatioMax {
                heldSeconds = 0
                reason = "behind_blurred"
                return .blur
            }
            guard let ratio = reading.behindFocusRatio, ratio >= thresholds.behindFocusRatioMin
            else {
                heldSeconds = 0
                return .none
            }
            if reading.speedFraction >= thresholds.tooFastSpeedFraction {
                restartAt = now
                clearCandidate()
                reason = "speed_spike"
                return .none
            }
            // Holding on a spot's target is not resting at an edge: a candidate that began as
            // the helper got there builds nothing from the stillness. A real edge reached on
            // the way to a spot began earlier and is still confirmed.
            if let reached = spotReachedAt, since > reached - thresholds.spotHoldSeconds + 1e-9 {
                heldSeconds = 0
                reason = "spot_hold"
                return .none
            }
            reason = arrived ? "arrived" : "vouched"
            return confirmWhenStill(reading, step: step)
        case .wholeBoxLowDetail:
            // As for the half rule: no arrival is only blur when the last tracked half behind
            // does not vouch for the content (the position is frozen while paused, so a helper
            // who set off just before the glass began shows no travel).
            let vouched = (lastTrackedBehind ?? 0) >= thresholds.behindFocusRatioMin
            // Never confirmed on a timer: a long blur is decided when detail returns (the
            // route does that), not by waiting.
            guard arrived || vouched else {
                reason = "not_arrived"
                return .blur
            }
            if let ahead = lastTrackedAhead, let behind = lastTrackedBehind,
                ahead < thresholds.blurFocusRatioMax, behind < thresholds.blurFocusRatioMax
            {
                reason = "behind_blurred"
                return .blur
            }
            reason = arrived ? "arrived" : "vouched"
            return confirmWhenStill(reading, step: step)
        }
    }

    /// The same for both candidates: the time held counts only while the helper is still and
    /// goes back to zero on any reading that is not, and the edge is confirmed once it has held
    /// `confirmSeconds` AND the slide has been still that long in a row. While moving the
    /// candidate is still reported (checking, 0) so it can be shown.
    private mutating func confirmWhenStill(_ reading: GuideReading, step: Double) -> EdgeVerdict {
        guard reading.isStill else {
            heldSeconds = 0
            reason = "moving"
            return .checking(progress: 0)
        }
        heldSeconds += step
        if heldSeconds >= thresholds.confirmSeconds - 1e-9,
            reading.isStill(for: thresholds.confirmSeconds)
        {
            return .confirmed
        }
        return .checking(progress: min(heldSeconds / thresholds.confirmSeconds, 1))
    }

    mutating func reset() {
        self = EdgeConfirmation(thresholds: thresholds, halfCut: halfCut)
    }

    /// Drops the candidate (a new target, a decision taken) but keeps the position history, so
    /// the arrival at the next edge can still be measured.
    mutating func cancel() {
        clearCandidate()
    }

    private mutating func clearCandidate() {
        activeKind = .none
        activeSince = nil
        heldSeconds = 0
        arrived = false
    }

    /// How far the view travelled along `heading` in the `window` seconds before `start`.
    private static func arrival(
        history: [(seconds: Double, position: CGPoint)], start: Double, heading: CGPoint?,
        window: Double
    ) -> Double {
        guard let heading else { return 0 }
        guard let atStart = history.last(where: { $0.seconds <= start + 1e-9 }),
            let earliest = history.first(where: { $0.seconds >= start - window - 1e-9 })
        else { return 0 }
        let dx = Double(atStart.position.x - earliest.position.x)
        let dy = Double(atStart.position.y - earliest.position.y)
        return max(0, dx * Double(heading.x) + dy * Double(heading.y))
    }
}
