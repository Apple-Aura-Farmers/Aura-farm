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
        let other: StageAxis = servo == .x ? .y : .x
        let dominant = move(servo, degrees(of: servo, in: needed), angles)
        guard case .atLimit = dominant else { return dominant }
        // The main servo is pinned: the other one may still help.
        if case .move = move(other, degrees(of: other, in: needed), angles) {
            return move(other, degrees(of: other, in: needed), angles)
        }
        return dominant
    }

    private func degrees(of servo: StageAxis, in needed: (x: Double, y: Double)) -> Double {
        servo == .x ? needed.x : needed.y
    }

    /// One servo's move for `degrees`: idle for under one degree, at limit when pinned.
    private func move(_ servo: StageAxis, _ degrees: Double, _ angles: (x: Int, y: Int)) -> StageMove {
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
