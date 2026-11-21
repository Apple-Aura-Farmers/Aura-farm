import CoreGraphics
import Foundation

enum StageMove: Equatable {
    case idle
    case move(servo: StageAxis, toAngle: Int)
    case atLimit(StageAxis)
}

/// Decides the next single-servo move that brings the picture toward the guide's target.
struct StageMotionPlanner {
    var mapping: StageServoMapping
    var chunkDegrees = 3
    var deadbandFields = 0.15

    /// - Parameters:
    ///   - angles: where the servos are now.
    ///   - target: vector to the target, in fields (nil when there is none).
    func next(angles: (x: Int, y: Int), target: CGPoint?) -> StageMove {
        guard let target, hypot(Double(target.x), Double(target.y)) >= deadbandFields,
            let needed = mapping.degrees(forMove: target)
        else { return .idle }
        let servo: StageAxis = abs(needed.x) >= abs(needed.y) ? .x : .y
        let degrees = servo == .x ? needed.x : needed.y
        guard degrees != 0 else { return .idle }
        let chunk = Double(min(max(chunkDegrees, 1), 10))
        let step = Int(min(max(degrees, -chunk), chunk).rounded())
        // Closer than one degree is not possible: stop here instead of hunting.
        guard step != 0 else { return .idle }
        let current = servo == .x ? angles.x : angles.y
        let angle = min(max(current + step, 0), 180)
        return angle == current ? .atLimit(servo) : .move(servo: servo, toAngle: angle)
    }
}
