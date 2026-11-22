import Foundation

/// Spots a patch with no detail: the guide waits for the picture, or the view is blank or blurry.
/// Moves do not matter (the preset path moves every second); only a frame with detail restarts
/// the count. Once the stretch is long enough the person is asked to refocus.
struct StageStallWatch {
    var noDetailSeconds = 2.0
    /// A view is sharp (so probably empty) when its focus index is at least this share of the
    /// baseline.
    var focusShareOfBaseline = 0.8

    enum Kind: Equatable { case sharp, blurry }

    private var since: Date?
    private var fired = false

    /// - Parameters:
    ///   - noDetail: the guide holds for the picture, or the view is blank or blurry.
    ///   - hasDetail: a frame with sample or thin detail while tracking. A frame that is neither
    ///     leaves the count as it is.
    /// - Returns: true once per stretch without detail.
    mutating func update(now: Date, noDetail: Bool, hasDetail: Bool) -> Bool {
        if hasDetail {
            since = nil
            fired = false
            return false
        }
        guard noDetail else { return false }
        let start = since ?? now
        since = start
        guard !fired, now.timeIntervalSince(start) >= noDetailSeconds else { return false }
        fired = true
        return true
    }

    /// Sharp when the focus index is at least `focusShareOfBaseline` of the baseline; blurry
    /// otherwise, and when either number is missing.
    func kind(focusIndex: Double?, baseline: Double?) -> Kind {
        guard let focusIndex, let baseline, baseline > 0 else { return .blurry }
        return focusIndex >= focusShareOfBaseline * baseline ? .sharp : .blurry
    }
}
