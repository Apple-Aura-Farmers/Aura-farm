import Foundation

/// The stage lost power and started again: its servos jump to 90. What the app saved when the
/// link dropped says where they were, and how to walk them back.
enum StageRestart {
    /// A reported angle further than this from the saved one means a restart.
    static let toleranceDegrees = 1

    static func detected(saved: (x: Int, y: Int), reported: (x: Int, y: Int)) -> Bool {
        abs(saved.x - reported.x) > toleranceDegrees || abs(saved.y - reported.y) > toleranceDegrees
    }

    /// The next move of the walk back: Y first, then X, at most `chunk` degrees at a time; nil
    /// once both servos are at the saved angles.
    static func nextStep(
        from current: (x: Int, y: Int), to saved: (x: Int, y: Int), chunk: Int
    ) -> (servo: StageAxis, angle: Int)? {
        let chunk = max(chunk, 1)
        func step(_ now: Int, _ target: Int) -> Int {
            now + max(-chunk, min(chunk, target - now))
        }
        if current.y != saved.y { return (.y, step(current.y, saved.y)) }
        if current.x != saved.x { return (.x, step(current.x, saved.x)) }
        return nil
    }
}
