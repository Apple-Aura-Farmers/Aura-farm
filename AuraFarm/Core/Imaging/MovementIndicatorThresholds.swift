import Foundation

/// The numbers `MovementIndicators` judges with. Data, not logic.
struct MovementIndicatorThresholds {
    /// Frame-to-frame movement per analyzed frame, as a share of the frame's short side.
    /// Below this is a comfortable speed. PLACEHOLDER: not calibrated.
    var comfortableSpeedFraction: Double = 0.08
    /// At or above this, tracking is at risk: the next reading may jump past what can be
    /// matched. PLACEHOLDER: not calibrated.
    var tooFastSpeedFraction: Double = 0.18
    /// Readings averaged for the speed meter. PLACEHOLDER: not calibrated.
    var speedWindow: Int = 3
    /// Frame-to-frame movement below this many px counts as still. PLACEHOLDER: not calibrated.
    var stillPixels: Double = 2
    /// Radius of the "home zone" around the marked start, in frames. PLACEHOLDER: not
    /// calibrated.
    var homeZoneFrames: Double = 0.25
}
