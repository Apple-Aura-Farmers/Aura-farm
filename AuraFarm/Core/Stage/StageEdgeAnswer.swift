import Foundation

/// When the automated stage answers an edge question by itself: each question once, after it has
/// stood for a moment (the stage has stopped by then). Pure; the time comes in.
struct StageEdgeAnswer {
    var waitSeconds = 1.0

    private var since: Date?
    private var waitingID: Int?
    private var answeredID: Int?

    /// Called while the guide asks. Returns the question to answer now, or nil.
    mutating func update(questionID: Int?, now: Date) -> Int? {
        guard let id = questionID, id != answeredID else { return nil }
        if waitingID != id {
            waitingID = id
            since = now
        }
        guard let since, now.timeIntervalSince(since) >= waitSeconds else { return nil }
        answeredID = id
        return id
    }

    /// The guide stopped asking: the next question waits its own moment.
    mutating func questionGone() {
        waitingID = nil
        since = nil
        answeredID = nil  // the guide's ids start again with each run
    }
}
