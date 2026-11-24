import CoreGraphics
import Foundation

/// What the analysis does while the stage is moved by hand (see `ScanEngine.setHandHold`).
enum StageHandHold: Equatable {
    /// As usual.
    case off
    /// The guide is held, focus is not judged, detections are shown but not counted.
    case on
    /// Back in place: the guide is held and focus is judged, nothing is counted.
    case checkingFocus
}

/// The four arrows of hand control. Left and right are always servo X, up and down servo Y:
/// never both servos at once.
enum StageArrow: CaseIterable {
    case up, down, left, right

    var axis: StageAxis { self == .left || self == .right ? .x : .y }

    /// For "Stage limit: X can't go further right".
    var word: String {
        switch self {
        case .up: "up"
        case .down: "down"
        case .left: "left"
        case .right: "right"
        }
    }
}

/// How the stage is steered: with the arrows (manual, no calibration), or by itself.
enum StageControlMode: String { case manual, autonomous }

/// Which way each arrow turns its servo. Not flipped: Right is more X degrees, Up more Y
/// degrees (the Stage control lab's own arrows); a flip turns that servo's pair round.
struct StageArrowDirections: Equatable {
    private let right: Int
    private let up: Int

    init(flipX: Bool = false, flipY: Bool = false) {
        right = flipX ? -1 : 1
        up = flipY ? -1 : 1
    }

    func sign(_ arrow: StageArrow) -> Int {
        switch arrow {
        case .right: right
        case .left: -right
        case .up: up
        case .down: -up
        }
    }

    /// The angle one press goes to, clamped to the range; nil when the servo is at the end.
    func nextAngle(_ arrow: StageArrow, from current: Int, step: Int, limits: StageLimits) -> Int? {
        let next = limits.clamp(current + sign(arrow) * max(step, 1), arrow.axis)
        return next == current ? nil : next
    }
}

/// Which arrow is in use. One at a time: it stays the active one until the finger is up AND its
/// move has settled; the other three are off meanwhile. A tap is one step; a press that stays
/// down goes on, one move at a time.
struct StageHandControl: Equatable {
    private(set) var active: StageArrow?
    private var held = false
    /// The press's own step is not sent yet (a tap is exactly this one step).
    private var tapPending = false
    private var moving = false
    /// The arrow met a limit while down: no more moves until it is pressed again.
    private var stalled = false

    /// Accepted when no arrow is active, or this one is.
    mutating func press(_ arrow: StageArrow) -> Bool {
        guard active == nil || active == arrow else { return false }
        active = arrow
        held = true
        tapPending = true
        stalled = false
        return true
    }

    mutating func release() {
        held = false
        clearIfIdle()
    }

    /// A move of the active arrow was sent: another follows only while the press stays down.
    mutating func sent() {
        moving = true
        tapPending = false
    }

    /// The active arrow cannot go further: no move, and none follows until it is pressed again.
    mutating func blocked() {
        tapPending = false
        stalled = true
        clearIfIdle()
    }

    /// The move settled (its POS came, or it was given up on).
    mutating func settled() {
        moving = false
        clearIfIdle()
    }

    /// Everything off, for a leave of hand control.
    mutating func reset() { self = StageHandControl() }

    /// A press or a tap waits for its move, and none is on its way.
    var wantsMove: Bool { active != nil && !moving && (tapPending || (held && !stalled)) }

    private mutating func clearIfIdle() {
        if !held, !moving, !tapPending { active = nil }
    }

    /// False for the three other arrows while one is active, and for an arrow at its limit.
    func enabled(
        _ arrow: StageArrow, directions: StageArrowDirections, angles: (x: Int, y: Int),
        step: Int, limits: StageLimits
    ) -> Bool {
        if let active, active != arrow { return false }
        let current = arrow.axis == .x ? angles.x : angles.y
        return directions.nextAngle(arrow, from: current, step: step, limits: limits) != nil
    }
}
