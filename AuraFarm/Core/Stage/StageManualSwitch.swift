import Foundation

/// The change-over from an autonomous run to steering with the arrows (the page's Auto | Manual
/// switch): what allows it, and the asking of the board whether it is idle. Pure: it decides, the
/// driver sends. The only commands behind it are STOP (the driver's own pause) and STATUS; it never
/// sends a move.
struct StageManualSwitch {
    enum State: Equatable { case idle, switching }

    /// What a STATUS answer said.
    struct Reading: Equatable {
        var x: Int
        var y: Int
        var isIdle: Bool
    }

    enum Outcome: Equatable {
        /// The board is idle at these angles: manual starts.
        case entered(x: Int, y: Int)
        /// No answer, or not idle, after every try: the run stays paused.
        case didNotAnswer
    }

    /// The least time between the STOP and the first STATUS, and between two STATUS. PLACEHOLDER.
    static let stopToStatusSeconds = 0.5
    static let askGapSeconds = 0.3
    /// STATUS is asked at most this often. PLACEHOLDER.
    static let maxAsks = 3

    /// What the page says when the board did not become idle.
    static let didNotAnswerText = "The stage did not answer. Try Manual again or Resume."

    private(set) var state = State.idle
    private var token = 0
    private var asks = 0

    /// Starts a change-over: its token, or nil while one is under way (one at a time).
    mutating func begin() -> Int? {
        guard state == .idle else { return nil }
        state = .switching
        asks = 0
        token += 1
        return token
    }

    /// `token` is the change-over under way (a cancelled one is not).
    func isCurrent(_ token: Int) -> Bool { state == .switching && self.token == token }

    /// A disconnect, the app in the background, End run, Stop and discard, the page closing, or
    /// Resume: no manual, no problem shown.
    mutating func cancel() {
        guard state == .switching else { return }
        state = .idle
        token += 1
    }

    /// How long to wait before the next STATUS; nil when the tries are used up.
    func nextAsk(sinceStop: Double, sinceLastAsk: Double?) -> Double? {
        guard asks < Self.maxAsks else { return nil }
        let afterStop = Self.stopToStatusSeconds - sinceStop
        let afterAsk = sinceLastAsk.map { Self.askGapSeconds - $0 } ?? 0
        return max(afterStop, afterAsk, 0)
    }

    /// A STATUS try ended with `reading` (nil: no answer). The outcome once there is one, nil to
    /// ask again.
    mutating func record(_ reading: Reading?) -> Outcome? {
        guard state == .switching else { return nil }
        asks += 1
        if let reading, reading.isIdle {
            state = .idle
            return .entered(x: reading.x, y: reading.y)
        }
        guard asks >= Self.maxAsks else { return nil }
        state = .idle
        return .didNotAnswer
    }

    /// A run that is not paused is paused (STOP) before anything else; a paused one is left as it is.
    static func needsPause(_ phase: AutoStageDriver.Phase) -> Bool { phase != .paused }

    /// The position hand control comes back to: one saved earlier stays the saved one.
    static func saved(
        existing: (x: Int, y: Int)?, reported: (x: Int, y: Int)
    ) -> (x: Int, y: Int) { existing ?? reported }

    /// Whether the run may be switched to manual: autonomous, connected, a path that has started
    /// and is not finished, and one of the phases where the stage is running or waiting for the
    /// person (a pause for focus is the run monitor's, so the phase is still `following`).
    static func canSwitch(
        phase: AutoStageDriver.Phase, isAutonomous: Bool, isConnected: Bool, pathRuns: Bool,
        sessionEnded: Bool, walkingBack: Bool, hasSummary: Bool, isCalibrating: Bool
    ) -> Bool {
        guard isAutonomous, isConnected, pathRuns, !sessionEnded, !walkingBack, !hasSummary,
            !isCalibrating
        else { return false }
        switch phase {
        case .following, .presetPath, .waitingForEdgeAnswer, .atLimit, .crossingEmpty,
            .emptyCapReached, .paused, .returningFromHand, .checkingFocus:
            return true
        default:
            return false
        }
    }
}
