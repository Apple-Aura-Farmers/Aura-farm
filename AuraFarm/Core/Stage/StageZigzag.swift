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
    var legSlackDegrees: Double
    var stepSlackDegrees: Double
    /// Column spacing and spot spacing, in fields.
    var stepFields = 0.8
    /// Degrees kept beyond a learned edge.
    var rangeMargin = 3
    var minChunk: Int
    /// The leg servo's end that puts the view at screen-top, and the step servo's end that
    /// puts it at screen-left (true: 180, false: 0).
    var legStartsHigh: Bool
    var stepStartsHigh: Bool

    init?(mapping: StageServoMapping, minChunk: Int) {
        // The servo that moves the picture more vertically walks the columns.
        let legIsX = mapping.swapped
        let leg = legIsX ? mapping.x : mapping.y
        let step = legIsX ? mapping.y : mapping.x
        legServo = legIsX ? .x : .y
        stepServo = legIsX ? .y : .x
        legFieldsPerDegree = hypot(Double(leg.x), Double(leg.y))
        stepFieldsPerDegree = hypot(Double(step.x), Double(step.y))
        guard legFieldsPerDegree > 0, stepFieldsPerDegree > 0 else { return nil }
        legSlackDegrees = legIsX ? mapping.xSlackDegrees : mapping.ySlackDegrees
        stepSlackDegrees = legIsX ? mapping.ySlackDegrees : mapping.xSlackDegrees
        self.minChunk = minChunk
        // More turn moves the view by the servo's vector: top is a negative y, left a negative x.
        legStartsHigh = leg.y < 0
        stepStartsHigh = step.x < 0
    }

    var columnStepDegrees: Int {
        max(minChunk, Int((stepFields / stepFieldsPerDegree).rounded()))
    }

    var spotStepDegrees: Int {
        max(minChunk, Int((stepFields / legFieldsPerDegree).rounded()))
    }

    var summary: String {
        "leg servo \(legServo.letter), column step \(columnStepDegrees)°, spot step \(spotStepDegrees)°"
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

/// The zig-zag as a state machine: go to the start corner, then for each column move the leg
/// servo one spot at a time with a dwell at each, and at the end of a leg step across and turn
/// round. The caller sends the moves and the dwells, and says when they are done.
struct StageZigzag {
    let plan: StageZigzagPlan
    var dwellSeconds: Double

    private(set) var column = 0
    private(set) var spot = 0
    private(set) var isFinished = false
    private(set) var lowEdge: Int?
    private(set) var highEdge: Int?

    private enum Stage { case approachLeg, approachStep, legDwell, legMove, stepMove, done }
    private var stage = Stage.approachLeg
    private var queue: [StageZigzagAction] = []
    private var direction: Int
    private var needsSlack = true
    private var started = false

    init(plan: StageZigzagPlan, dwellSeconds: Double = 1.2) {
        self.plan = plan
        self.dwellSeconds = dwellSeconds
        // From the start end toward the other.
        direction = plan.legStartsHigh ? -1 : 1
    }

    /// The next thing to do, or nil while waiting for an event. Call again after the caller has
    /// handled an action that needs no waiting (columnStarted / columnEnded).
    mutating func next(angles: (x: Int, y: Int), event: StageZigzagEvent?) -> StageZigzagAction? {
        if !started {
            started = true
            queueMove(plan.legServo, to: plan.legStartsHigh ? 180 : 0, angles)
            if queue.isEmpty { handle(.settled, angles) }  // already at the start end
        }
        if let event { handle(event, angles) }
        return queue.isEmpty ? nil : queue.removeFirst()
    }

    // MARK: Events

    private mutating func handle(_ event: StageZigzagEvent, _ angles: (x: Int, y: Int)) {
        switch (stage, event) {
        case (.approachLeg, .settled):
            stage = .approachStep
            queueMove(plan.stepServo, to: plan.stepStartsHigh ? 180 : 0, angles)
        case (.approachStep, .settled):
            beginColumn()
        case (.legDwell, .dwellDone):
            nextSpot(angles)
        case (.legMove, .settled):
            spot += 1
            stage = .legDwell
            queue.append(.dwell(seconds: dwellSeconds))
        case (.stepMove, .settled):
            beginColumn()
        case (.legDwell, .edge), (.legMove, .edge):
            edgeReached(angles)
        default:
            break
        }
        // A move to where the servo already is gets no reply: carry straight on.
        if stage == .approachStep, queue.isEmpty { handle(.settled, angles) }
    }

    private mutating func beginColumn() {
        column += 1
        spot = 1
        if column > 1 { direction = -direction }
        needsSlack = true
        stage = .legDwell
        queue.append(.columnStarted(column))
        queue.append(.dwell(seconds: dwellSeconds))
    }

    private func bounds() -> (low: Int, high: Int) {
        let low = lowEdge.map { max($0 - plan.rangeMargin, 0) } ?? 0
        let high = highEdge.map { min($0 + plan.rangeMargin, 180) } ?? 180
        return (low, high)
    }

    private func angle(of servo: StageAxis, _ angles: (x: Int, y: Int)) -> Int {
        servo == .x ? angles.x : angles.y
    }

    private mutating func nextSpot(_ angles: (x: Int, y: Int)) {
        let current = angle(of: plan.legServo, angles)
        let range = bounds()
        let slack = needsSlack ? Int(plan.legSlackDegrees.rounded()) : 0
        let target = min(
            max(current + direction * (plan.spotStepDegrees + slack), range.low), range.high)
        guard target != current else { return endLeg(angles) }
        needsSlack = false
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
        let stepDirection = plan.stepStartsHigh ? -1 : 1
        let far = plan.stepStartsHigh ? 0 : 180
        guard current != far else {
            stage = .done
            isFinished = true
            queue.append(.finished("end of range"))
            return
        }
        let target = min(
            max(current + stepDirection * plan.columnStepDegrees, 0), 180)
        stage = .stepMove
        queue.append(.moveTo(servo: plan.stepServo, angle: target))
    }

    private mutating func queueMove(_ servo: StageAxis, to angle: Int, _ angles: (x: Int, y: Int)) {
        guard self.angle(of: servo, angles) != angle else { return }
        queue.append(.moveTo(servo: servo, angle: angle))
    }
}
