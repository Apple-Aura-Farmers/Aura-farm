import Foundation

/// A test's first connection to the stage: before anything else moves it, the stage goes to
/// X=90, Y=90. Once per test; a reconnect finds it over. Pure: it decides, the driver sends.
struct StageCentring: Equatable {
    static let angle = 90
    /// How long a connected board may take to say where it is before the test carries on without
    /// centring. PLACEHOLDER.
    static let positionWaitSeconds = 3.0

    enum State: Equatable {
        case waiting(since: Date?)
        case centring, over
    }

    /// What a connected tick does: hold the stage, start centring, give up, or go on as usual.
    enum Step: Equatable { case hold, centre, noPosition, carryOn }

    private(set) var state = State.waiting(since: nil)

    /// Nothing else may move the stage yet.
    var isPending: Bool { state != .over }
    var isCentring: Bool { state == .centring }

    mutating func connectedTick(positionKnown: Bool, now: Date) -> Step {
        guard case .waiting(let since) = state else { return isCentring ? .hold : .carryOn }
        if positionKnown {
            state = .centring
            return .centre
        }
        let start = since ?? now
        if now.timeIntervalSince(start) >= Self.positionWaitSeconds {
            state = .over
            return .noPosition
        }
        state = .waiting(since: start)
        return .hold
    }

    /// The link dropped before the board said where it was: the wait starts again.
    mutating func dropped() {
        if case .waiting = state { state = .waiting(since: nil) }
    }

    /// Centred or failed: either way the test goes on, and it is not tried again.
    mutating func finish() { state = .over }

    /// The servos to move, X first; one already at 90 is left out.
    static func moves(x: Int, y: Int) -> [StageAxis] {
        [(StageAxis.x, x), (.y, y)].filter { $0.1 != angle }.map(\.0)
    }
}
