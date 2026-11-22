import CoreGraphics
import Foundation

/// How the automated stage moves: following the guide, or a preset zig-zag in servo angles.
enum StagePathMode: String, CaseIterable {
    case followGuide, presetPath

    var title: String { self == .followGuide ? "Follow guide" : "Follow preset path" }
}

/// The zig-zag laid out from the servo mapping: columns run up and down the screen like the
/// guide's, the step servo moves one column across at a time.
///
/// Screen coordinates are the guide's: x to the right, y down, so "top" is the smaller y.
struct StageZigzagPlan: Equatable {
    var legServo: StageAxis
    var stepServo: StageAxis
    var legFieldsPerDegree: Double
    var stepFieldsPerDegree: Double
    /// Distance between stops along a leg and between columns, in fields.
    var stepFields = 0.8
    /// Degrees kept beyond a learned edge.
    var rangeMargin = 3
    /// The leg servo's end that puts the view at screen-top, and the step servo's end that
    /// puts it at screen-left (true: 180, false: 0).
    var legStartsHigh: Bool
    var stepStartsHigh: Bool

    init?(mapping: StageServoMapping) {
        // The servo that moves the picture more vertically walks the columns.
        let legIsX = mapping.swapped
        let leg = legIsX ? mapping.x : mapping.y
        let step = legIsX ? mapping.y : mapping.x
        legServo = legIsX ? .x : .y
        stepServo = legIsX ? .y : .x
        legFieldsPerDegree = hypot(Double(leg.x), Double(leg.y))
        stepFieldsPerDegree = hypot(Double(step.x), Double(step.y))
        guard legFieldsPerDegree > 0, stepFieldsPerDegree > 0 else { return nil }
        // More turn moves the view by the servo's vector: top is a negative y, left a negative x.
        legStartsHigh = leg.y < 0
        stepStartsHigh = step.x < 0
    }
}

enum StageZigzagEvent: Equatable {
    /// The move that was asked for is done.
    case settled
    /// The view has left the sample.
    case edge
    /// The dwell is over.
    case dwellDone
}

enum StageZigzagAction: Equatable {
    case moveTo(servo: StageAxis, angle: Int)
    case dwell(seconds: Double)
    case columnStarted(Int)
    case columnEnded(Int)
    case finished(String)
}

/// The zig-zag as a state machine: walk to the start corner, then for each column walk the leg
/// servo with a dwell every `stepFields` of picture travel, and at the end of a leg walk the
/// step servo across and turn round. No move is longer than `chunkDegrees`. The caller sends
/// the moves and the dwells, and says when they are done.
struct StageZigzag {
    let plan: StageZigzagPlan
    var dwellSeconds: Double
    var chunkDegrees: Int
    /// Live fields per degree; the degree fallbacks use these (a mapping correction updates them).
    var legFieldsPerDegree: Double
    var stepFieldsPerDegree: Double

    private(set) var column = 0
    private(set) var spot = 0
    private(set) var isFinished = false
    private(set) var lowEdge: Int?
    private(set) var highEdge: Int?

    private enum Stage { case approachLeg, approachStep, legDwell, legMove, stepMove, done }
    private var stage = Stage.approachLeg
    private var queue: [StageZigzagAction] = []
    private var direction: Int
    private var started = false
    private var tracked: CGPoint?
    private var anchorPosition: CGPoint?
    private var anchorAngle = 0

    init(plan: StageZigzagPlan, chunkDegrees: Int, dwellSeconds: Double = 1.2) {
        self.plan = plan
        self.chunkDegrees = max(chunkDegrees, 1)
        self.dwellSeconds = dwellSeconds
        legFieldsPerDegree = plan.legFieldsPerDegree
        stepFieldsPerDegree = plan.stepFieldsPerDegree
        // From the start end toward the other.
        direction = plan.legStartsHigh ? -1 : 1
    }

    /// Degrees between stops along a leg when the picture position is not known.
    var legFallbackDegrees: Int {
        max(chunkDegrees, Int((plan.stepFields / legFieldsPerDegree).rounded()))
    }

    /// Degrees of a column step when the picture position is not known.
    var columnFallbackDegrees: Int {
        max(chunkDegrees, Int((plan.stepFields / stepFieldsPerDegree).rounded()))
    }

    var summary: String {
        "leg servo \(plan.legServo.letter), step \(chunkDegrees)°, stops every "
            + "\(plan.stepFields) field (fallback \(legFallbackDegrees)° leg / "
            + "\(columnFallbackDegrees)° column)"
    }

    /// Sets the live fields per degree of each servo (x, y).
    mutating func setFieldsPerDegree(x: Double, y: Double) {
        let leg = plan.legServo == .x ? x : y
        let step = plan.legServo == .x ? y : x
        if leg > 0 { legFieldsPerDegree = leg }
        if step > 0 { stepFieldsPerDegree = step }
    }

    /// The next thing to do, or nil while waiting for an event. Call again after the caller has
    /// handled an action that needs no waiting (columnStarted / columnEnded). `tracked` is the
    /// picture position in fields, nil when the tracker has no fresh reading.
    mutating func next(
        angles: (x: Int, y: Int), event: StageZigzagEvent?, tracked: CGPoint? = nil
    ) -> StageZigzagAction? {
        self.tracked = tracked
        if !started {
            started = true
            approach(angles)
        }
        if let event { handle(event, angles) }
        return queue.isEmpty ? nil : queue.removeFirst()
    }

    // MARK: Events

    private mutating func handle(_ event: StageZigzagEvent, _ angles: (x: Int, y: Int)) {
        switch (stage, event) {
        case (.approachLeg, .settled), (.approachStep, .settled):
            approach(angles)
        case (.legDwell, .dwellDone):
            legStep(angles)
        case (.legMove, .settled):
            if legStopReached(angles) {
                spot += 1
                startDwell(angles)
            } else {
                legStep(angles)
            }
        case (.stepMove, .settled):
            stepStep(angles)
        case (.legDwell, .edge), (.legMove, .edge):
            edgeReached(angles)
        default:
            break
        }
    }

    private func angle(of servo: StageAxis, _ angles: (x: Int, y: Int)) -> Int {
        servo == .x ? angles.x : angles.y
    }

    /// One step of at most `chunkDegrees` from `current` toward `end`.
    private func stepToward(_ end: Int, from current: Int) -> Int {
        current + max(-chunkDegrees, min(chunkDegrees, end - current))
    }

    private mutating func approach(_ angles: (x: Int, y: Int)) {
        let legEnd = plan.legStartsHigh ? 180 : 0
        let stepEnd = plan.stepStartsHigh ? 180 : 0
        let leg = angle(of: plan.legServo, angles)
        let step = angle(of: plan.stepServo, angles)
        if leg != legEnd {
            stage = .approachLeg
            queue.append(.moveTo(servo: plan.legServo, angle: stepToward(legEnd, from: leg)))
        } else if step != stepEnd {
            stage = .approachStep
            queue.append(.moveTo(servo: plan.stepServo, angle: stepToward(stepEnd, from: step)))
        } else {
            beginColumn(angles)
        }
    }

    private mutating func beginColumn(_ angles: (x: Int, y: Int)) {
        column += 1
        spot = 1
        if column > 1 { direction = -direction }
        queue.append(.columnStarted(column))
        startDwell(angles)
    }

    private mutating func startDwell(_ angles: (x: Int, y: Int)) {
        stage = .legDwell
        anchorPosition = tracked
        anchorAngle = angle(of: plan.legServo, angles)
        queue.append(.dwell(seconds: dwellSeconds))
    }

    private func bounds() -> (low: Int, high: Int) {
        let low = lowEdge.map { max($0 - plan.rangeMargin, 0) } ?? 0
        let high = highEdge.map { min($0 + plan.rangeMargin, 180) } ?? 180
        return (low, high)
    }

    /// True once the picture has moved `stepFields` since the last dwell (or, without a
    /// tracked position, the degree fallback has been walked).
    private func legStopReached(_ angles: (x: Int, y: Int)) -> Bool {
        if let tracked, let anchorPosition {
            return hypot(tracked.x - anchorPosition.x, tracked.y - anchorPosition.y) >= plan.stepFields
        }
        return abs(angle(of: plan.legServo, angles) - anchorAngle) >= legFallbackDegrees
    }

    private mutating func legStep(_ angles: (x: Int, y: Int)) {
        let current = angle(of: plan.legServo, angles)
        let range = bounds()
        let end = direction > 0 ? range.high : range.low
        let target = stepToward(end, from: current)
        guard target != current else { return endLeg(angles) }
        stage = .legMove
        queue.append(.moveTo(servo: plan.legServo, angle: target))
    }

    private mutating func edgeReached(_ angles: (x: Int, y: Int)) {
        // An edge at the very first spot of a later column: the whole column is beyond it.
        if column > 1, spot == 1, stage == .legDwell {
            stage = .done
            isFinished = true
            queue.append(.columnEnded(column))
            queue.append(.finished("edge at the start of column \(column)"))
            return
        }
        let current = angle(of: plan.legServo, angles)
        if direction > 0 { highEdge = current } else { lowEdge = current }
        endLeg(angles)
    }

    private mutating func endLeg(_ angles: (x: Int, y: Int)) {
        queue.append(.columnEnded(column))
        let current = angle(of: plan.stepServo, angles)
        let far = plan.stepStartsHigh ? 0 : 180
        guard current != far else {
            stage = .done
            isFinished = true
            queue.append(.finished("end of range"))
            return
        }
        stage = .stepMove
        anchorPosition = tracked
        anchorAngle = current
        queue.append(.moveTo(servo: plan.stepServo, angle: stepToward(far, from: current)))
    }

    /// After a settled step of the column move: next column once the picture has moved a
    /// column's width (or the degree fallback, capped at twice that), else another step.
    private mutating func stepStep(_ angles: (x: Int, y: Int)) {
        let current = angle(of: plan.stepServo, angles)
        let far = plan.stepStartsHigh ? 0 : 180
        let moved = abs(current - anchorAngle)
        var arrived = moved >= 2 * columnFallbackDegrees || current == far
        if let tracked, let anchorPosition {
            arrived =
                arrived
                || hypot(tracked.x - anchorPosition.x, tracked.y - anchorPosition.y) >= plan.stepFields
        } else {
            arrived = arrived || moved >= columnFallbackDegrees
        }
        if arrived { return beginColumn(angles) }
        queue.append(.moveTo(servo: plan.stepServo, angle: stepToward(far, from: current)))
    }
}
