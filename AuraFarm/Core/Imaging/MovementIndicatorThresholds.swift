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
}
