import Foundation

/// The numbers `MovementIndicators` judges with. Data, not logic.
struct MovementIndicatorThresholds {
    /// Frame-to-frame movement per analyzed frame, as a share of the REFERENCE side: the
    /// registration box's side, or the frame's short side when the whole frame is used. The
    /// speed thresholds keep the values they had when the reference was always the frame's
    /// short side, so they now mean a share of the box; re-measure them.
    /// Below this is a comfortable speed. PLACEHOLDER: not calibrated.
    var comfortableSpeedFraction: Double = 0.08
    /// At or above this, tracking is at risk: the next reading may jump past what can be
    /// matched. PLACEHOLDER: not calibrated.
    var tooFastSpeedFraction: Double = 0.18
    /// Readings averaged for the speed meter. PLACEHOLDER: not calibrated.
    var speedWindow: Int = 3
    /// Frame-to-frame movement below this many px counts as still. PLACEHOLDER: not calibrated.
    var stillPixels: Double = 2
    /// Radius of the "home zone" around the marked start, in fields (one field being the
    /// registration box's side). PLACEHOLDER: not calibrated.
    var homeZoneFields: Double = 0.25
    /// Speed is shift per THIS many seconds: a frame is scaled by this over the gap since the
    /// frame before, so a dropped frame (a 0.17 s gap) does not read as a faster hand. PLACEHOLDER;
    /// source: the median analysed gap in the 14:20, 22:56 and 23:47 runs (0.100 to 0.130 s), which
    /// the speed thresholds were tuned at.
    var referenceIntervalSeconds: Double = 0.1
    /// The gap is clamped to this range before scaling, so a long stall or a near-duplicate
    /// timestamp cannot make a huge or a vanishing speed. PLACEHOLDER: half and three times the
    /// reference.
    var minIntervalSeconds: Double = 0.05
    var maxIntervalSeconds: Double = 0.30
}
