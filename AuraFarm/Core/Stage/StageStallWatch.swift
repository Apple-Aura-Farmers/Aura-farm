import Foundation

/// Spots a stall where the guide waits for the picture (blurry, nothing to follow) and the focus
/// index has dropped well below its baseline, so the run should pause for focus.
struct StageStallWatch {
    var holdSeconds = 3.0
    var focusShareOfBaseline = 0.8
    /// A stall this long fires whatever the focus numbers say (or when they are missing): an
    /// empty patch and a blurry view look alike, so the person is always asked first.
    var longStallSeconds = 6.0

    private var since: Date?
    private var fired = false

    /// - Parameters:
    ///   - holds: the guide is waiting for the picture right now.
    ///   - moved: a move was sent since the last call (the stall window starts again).
    /// - Returns: true once per stall, when it should pause for focus.
    mutating func update(
        now: Date, holds: Bool, moved: Bool, focusIndex: Double?, baseline: Double?
    ) -> Bool {
        guard holds else {
            since = nil
            fired = false
            return false
        }
        if moved || since == nil { since = now }
        guard !fired, let since else { return false }
        let held = now.timeIntervalSince(since)
        var low = false
        if let focusIndex, let baseline, baseline > 0 {
            low = focusIndex < focusShareOfBaseline * baseline
        }
        guard (held >= holdSeconds && low) || held >= longStallSeconds else { return false }
        fired = true
        return true
    }
}
