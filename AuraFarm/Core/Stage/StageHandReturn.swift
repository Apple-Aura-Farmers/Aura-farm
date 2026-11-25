import Foundation

/// The way back from where hand control left the stage to the saved angles: Y first, then X,
/// only the servos that moved, in steps of at most `chunk`. A servo that would come onto its
/// saved angle from the other side than its last real direction first goes past it, so the
/// linkage's slack is taken up the same way as before.
struct StageHandReturn {
    let saved: (x: Int, y: Int)
    let chunk: Int
    let limits: StageLimits
    /// Which servos moved by hand.
    let moved: (x: Bool, y: Bool)
    /// Each servo's last real direction before the takeover: +1, -1, or 0 (never moved).
    let direction: (x: Int, y: Int)

    /// How far past the saved angle a servo goes before coming back onto it.
    static let overshootDegrees = 3

    /// Per servo (X, Y): the angle to go past first, decided at its first step; and whether it
    /// was reached.
    private var past: [Int?] = [nil, nil]
    private var decided = [false, false]
    private var passed = [false, false]

    init(
        saved: (x: Int, y: Int), chunk: Int, limits: StageLimits = StageLimits(),
        moved: (x: Bool, y: Bool), direction: (x: Int, y: Int)
    ) {
        self.saved = saved
        self.chunk = max(chunk, 1)
        self.limits = limits
        self.moved = moved
        self.direction = direction
    }

    /// The next move, or nil when both servos are on their saved angles.
    mutating func nextStep(angles: (x: Int, y: Int)) -> (servo: StageAxis, angle: Int)? {
        if moved.y, let angle = step(.y, angles.y) { return (.y, angle) }
        if moved.x, let angle = step(.x, angles.x) { return (.x, angle) }
        return nil
    }

    private mutating func step(_ servo: StageAxis, _ current: Int) -> Int? {
        let i = servo == .x ? 0 : 1
        let target = servo == .x ? saved.x : saved.y
        if !decided[i] {
            decided[i] = true
            let last = servo == .x ? direction.x : direction.y
            // The servo last arrived moving in `last`; coming back from the other side would
            // arrive moving the other way, so go past the saved angle first.
            let arrivesMoving = current < target ? 1 : -1
            if last != 0, current != target, arrivesMoving != last {
                let beyond = limits.clamp(target - last * Self.overshootDegrees, servo)
                if (target - beyond) * last > 0 { past[i] = beyond }
            }
        }
        if let beyond = past[i], !passed[i] {
            if current != beyond { return stepToward(beyond, from: current) }
            passed[i] = true
        }
        return current == target ? nil : stepToward(target, from: current)
    }

    private func stepToward(_ goal: Int, from current: Int) -> Int {
        current + max(-chunk, min(chunk, goal - current))
    }
}
