import Foundation

/// Decides when the automated stage presses "Stage limit" for the person: once the servo is
/// pinned at 0 or 180, the guide has the final position, and nothing has been tried since.
struct StageLimitAutoPress {
    var settleSeconds = 1.0
    var retrySeconds = 6.0

    private var lastPress: Date?

    /// - Parameters:
    ///   - atLimit: the planner can only say "at limit" right now.
    ///   - lastSettledAt: when the last move (or stop) ended.
    ///   - movedSinceLastPress: a move was sent since the last press; this starts a new episode.
    /// - Returns: true when the button should be pressed now (the press time is recorded).
    mutating func update(
        now: Date, atLimit: Bool, lastSettledAt: Date, movedSinceLastPress: Bool
    ) -> Bool {
        if movedSinceLastPress { lastPress = nil }
        guard atLimit, now.timeIntervalSince(lastSettledAt) >= settleSeconds else { return false }
        if let last = lastPress, now.timeIntervalSince(last) < retrySeconds { return false }
        lastPress = now
        return true
    }
}
