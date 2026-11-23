import CoreGraphics
import Foundation

/// A blind crossing of an empty patch: the stage keeps going in one direction and the servo
/// angles say how far the picture moved, since the tracker has nothing to follow.
struct StageBlindCrossing {
    /// The way to go, a unit vector in raw guide fields (zero if none was given).
    let direction: CGPoint
    let startAngles: (x: Int, y: Int)
    private(set) var capFields: Double

    init(direction: CGPoint, startAngles: (x: Int, y: Int), capFields: Double = 2.0) {
        let length = hypot(Double(direction.x), Double(direction.y))
        self.direction =
            length > 0
            ? CGPoint(x: direction.x / length, y: direction.y / length) : .zero
        self.startAngles = startAngles
        self.capFields = capFields
    }

    mutating func extendCap(by fields: Double = 2.0) { capFields += fields }

    /// How far the picture has moved since the start, in raw guide fields.
    func movedFields(angles: (x: Int, y: Int), mapping: StageServoMapping) -> CGPoint {
        let dx = CGFloat(angles.x - startAngles.x)
        let dy = CGFloat(angles.y - startAngles.y)
        return CGPoint(
            x: mapping.x.x * dx + mapping.y.x * dy, y: mapping.x.y * dx + mapping.y.y * dy)
    }

    func distance(angles: (x: Int, y: Int), mapping: StageServoMapping) -> Double {
        let moved = movedFields(angles: angles, mapping: mapping)
        return hypot(Double(moved.x), Double(moved.y))
    }

    func reachedCap(angles: (x: Int, y: Int), mapping: StageServoMapping) -> Bool {
        distance(angles: angles, mapping: mapping) >= capFields
    }

    /// What the planner is aimed at: one field along the direction.
    func target() -> CGPoint { direction }
}
