import Foundation

/// When the lab's analysis counts as falling behind the camera. Data, not logic.
struct AnalysisLoadThresholds {
    /// A frame taking longer than this many milliseconds is too slow. PLACEHOLDER: not
    /// calibrated.
    var maxMilliseconds: Double = 100
    /// Fewer analyzed frames per second than this is too few. PLACEHOLDER: not calibrated.
    var minFramesPerSecond: Double = 5

    /// A rate of 0 means "not known yet" and is not a problem.
    func isFallingBehind(milliseconds: Double, framesPerSecond: Double) -> Bool {
        milliseconds > maxMilliseconds
            || (framesPerSecond > 0 && framesPerSecond < minFramesPerSecond)
    }
}
