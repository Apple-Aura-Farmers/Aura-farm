import CoreGraphics
import Foundation

/// The numbers `HopOdometer` decides with. Data, not logic.
struct HopOdometerThresholds {
    /// Re-anchor once the view has moved this share of the frame's SHORT side from the
    /// anchor. PLACEHOLDER: not calibrated.
    var hopFraction: Double = 0.3
    /// An offset beyond this share of the short side is not trusted (registration returns
    /// confident wrong answers past it). Mirrors `PanoramaStitcher.maxShiftFraction`.
    var maxTrustedFraction: Double = 0.4
    /// Readings in a row with no trusted offset before tracking counts as lost.
    /// PLACEHOLDER: not calibrated.
    var readingsToLose: Int = 3
    /// Used instead of `hopFraction` when the caller passes a `referenceSide`: re-anchor once
    /// the view has moved this share of the registration box's side. A hop must stay well
    /// inside the box, or the two frames hardly overlap there. PLACEHOLDER: not calibrated.
    var hopFractionOfBox: Double = 0.25
    /// Used instead of `maxTrustedFraction` with a `referenceSide`: an offset beyond this
    /// share of the box's side is not trusted. PLACEHOLDER: not calibrated.
    var maxTrustedFractionOfBox: Double = 0.4
}

/// Tracks where the view is from offsets measured against an anchor frame.
///
/// While the knob turns, the caller holds an anchor frame and measures the signed offset of
/// the live view against it. When that offset reaches a share of the frame (`hopFraction`)
/// it is added to a running position (a "hop") and the caller re-anchors on the current
/// frame. Hops overlap, so each is measured on ground both frames can see.
///
/// Sign convention: `position` is where the VIEW has travelled across the slide, in the
/// frame's own pixel axes, x to the right and y down (top-down, as `ShakeEstimator`
/// reports). It is in the same direction as the registered shift; content on the slide
/// appears to move the OPPOSITE way, see `CaptureViewModel.pictureMoved`.
///
/// There is no anchor before the first good frame. Anchoring on it is the caller's job: it
/// holds that frame and only then starts passing offsets. A nil offset means "measured, and
/// nothing trustworthy came back"; it is not "nothing to measure against yet", so the
/// caller must not feed nils while it has no anchor.
struct HopOdometer {
    enum Event: Equatable { case none, hop, lost, regained }

    var thresholds: HopOdometerThresholds

    /// The sum of finished hops, in px.
    private(set) var committed: CGPoint = .zero
    /// The current offset from the anchor, in px.
    private(set) var live: CGPoint = .zero
    private(set) var hops = 0
    /// Times tracking was lost and then regained.
    private(set) var gaps = 0
    private(set) var isLost = false
    private var untrustedStreak = 0

    init(thresholds: HopOdometerThresholds = HopOdometerThresholds()) {
        self.thresholds = thresholds
    }

    var position: CGPoint {
        CGPoint(x: committed.x + live.x, y: committed.y + live.y)
    }

    /// The position in fields, one field being the side of the registration box (the useful
    /// part of the view).
    func positionInFields(fieldSide: Double) -> CGPoint {
        guard fieldSide > 0 else { return .zero }
        return CGPoint(x: position.x / fieldSide, y: position.y / fieldSide)
    }

    /// The hop distance in px for the given sizes; what `update` hops at.
    func hopDistance(frameSize: CGSize, referenceSide: Double? = nil) -> Double {
        if let referenceSide { return thresholds.hopFractionOfBox * referenceSide }
        return thresholds.hopFraction * Double(min(frameSize.width, frameSize.height))
    }

    /// The position in frames, one frame being the frame's short side.
    func positionInFrames(shortSide: Double) -> CGPoint {
        guard shortSide > 0 else { return .zero }
        return CGPoint(x: position.x / shortSide, y: position.y / shortSide)
    }

    /// Feeds one measurement against the current anchor.
    ///
    /// The hop and trust limits are fractions of the frame's short side, or, when
    /// `referenceSide` is given, of that side (the registration box's), using
    /// `hopFractionOfBox` and `maxTrustedFractionOfBox`.
    ///
    /// - Returns: what happened, and whether the caller must re-anchor on the current frame.
    ///   After `.lost` the caller re-anchors too, so tracking restarts from where it was
    ///   last known; the position keeps its last committed + live, and that error is
    ///   accepted. A hop that lands while lost also counts as tracking regained (`gaps`
    ///   goes up) but is reported as `.hop`, the more important of the two.
    mutating func update(
        offset: CGPoint?, frameSize: CGSize, referenceSide: Double? = nil
    ) -> (event: Event, reanchor: Bool) {
        let shortSide = Double(min(frameSize.width, frameSize.height))
        let trusted =
            referenceSide.map { thresholds.maxTrustedFractionOfBox * $0 }
            ?? thresholds.maxTrustedFraction * shortSide
        let hopAt = hopDistance(frameSize: frameSize, referenceSide: referenceSide)

        guard let offset, hypot(offset.x, offset.y) <= trusted
        else {
            untrustedStreak += 1
            if untrustedStreak >= thresholds.readingsToLose && !isLost {
                isLost = true
                return (.lost, true)
            }
            return (.none, false)
        }

        untrustedStreak = 0
        live = offset
        let wasLost = isLost
        if wasLost {
            isLost = false
            gaps += 1
        }

        if hypot(offset.x, offset.y) >= hopAt {
            committed = position
            live = .zero
            hops += 1
            return (.hop, true)
        }
        return (wasLost ? .regained : .none, false)
    }

    /// Commits `offset` as a hop whatever its size, for a run of predicted readings that the
    /// caller has decided to trust. The caller re-anchors on the current frame.
    mutating func commit(offset: CGPoint) {
        untrustedStreak = 0
        let wasLost = isLost
        if wasLost {
            isLost = false
            gaps += 1
        }
        live = offset
        committed = position
        live = .zero
        hops += 1
    }

    /// Folds the live offset into the committed position without counting a hop, for when the
    /// caller re-anchors after a stretch with nothing to track. The position carries on from
    /// where it was last known.
    mutating func rebase() {
        committed = position
        live = .zero
        untrustedStreak = 0
    }

    mutating func reset() {
        committed = .zero
        live = .zero
        hops = 0
        gaps = 0
        isLost = false
        untrustedStreak = 0
    }
}
