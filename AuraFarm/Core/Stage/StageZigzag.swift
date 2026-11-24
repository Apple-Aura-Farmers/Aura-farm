import CoreGraphics
import Foundation

/// How the automated stage moves: following the guide, or a preset zig-zag in servo angles.
enum StagePathMode: String, CaseIterable {
    case followGuide, presetPath

    var title: String { self == .followGuide ? "Follow guide" : "Preset moves" }
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
    /// The two servos' roles were exchanged after the first column ran sideways.
    var rolesSwapped = false

    /// The path without calibration: servo Y walks the columns, servo X steps across, with the
    /// arrows' own directions (Up is more Y degrees, Left fewer X degrees, unless flipped), so it
    /// starts at the screen's top left.
    init(objective: StageObjective, flipX: Bool, flipY: Bool) {
        rolesSwapped = false
        legServo = .y
        stepServo = .x
        legFieldsPerDegree = objective.nominalFieldsPerDegree
        stepFieldsPerDegree = objective.nominalFieldsPerDegree
        legStartsHigh = !flipY
        stepStartsHigh = flipX
    }

    /// - Parameter swappingRoles: the other servo walks the columns (the first-column check).
    init?(mapping: StageServoMapping, swappingRoles: Bool = false) {
        rolesSwapped = swappingRoles
        // The servo that moves the picture more vertically walks the columns.
        let legIsX = mapping.swapped != swappingRoles
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
    /// Column 1 ran sideways: the roles were exchanged and the path starts again (the picture's
    /// travel in fields).
    case swapped(dx: Double, dy: Double)
}

/// How far the preset path has come, for a progress bar.
struct StageZigzagProgress: Equatable {
    /// 0 to 1; never falls during a path.
    var fraction = 0.0
    /// 0 on the way to the start corner.
    var column = 0
    /// An estimate: from the degrees left across and the size of a column step.
    var totalColumns = 0

    var text: String {
        guard column > 0 else { return "Moving to the start corner" }
        return "Column \(column) of about \(totalColumns) · \(Int((fraction * 100).rounded(.down)))%"
    }
}

/// The zig-zag as a state machine: walk to the start corner, then for each column walk the leg
/// servo with a dwell every `stepFields` of picture travel, and at the end of a leg walk the
/// step servo across and turn round. No move is longer than `chunkDegrees`. The caller sends
/// the moves and the dwells, and says when they are done.
struct StageZigzag {
    private(set) var plan: StageZigzagPlan
    var dwellSeconds: Double
    var chunkDegrees: Int
    /// Degrees added to the leg servo's and the step servo's moves while their gears are stuck.
    var boostLeg = 0
    var boostStep = 0
    /// The angles the servos may reach; may change while the path runs (the board refused a move).
    var limits = StageLimits()
    /// The current mapping (kept up to date by the caller); used to rebuild the plan on a swap.
    var mapping: StageServoMapping?
    /// Picture travel in column 1 that is enough to tell its direction, in fields.
    static let swapCheckFields = 1.0
    /// Live fields per degree; the degree fallbacks use these (a mapping correction updates them).
    var legFieldsPerDegree: Double
    var stepFieldsPerDegree: Double

    private(set) var column = 0
    private(set) var spot = 0
    private(set) var isFinished = false
    private(set) var progress = StageZigzagProgress()
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
    private var swapAnchor: CGPoint?
    private var swapCheckOpen = true

    init(plan: StageZigzagPlan, chunkDegrees: Int, dwellSeconds: Double = 1.2) {
        self.plan = plan
        self.chunkDegrees = max(chunkDegrees, 1)
        self.dwellSeconds = dwellSeconds
        legFieldsPerDegree = plan.legFieldsPerDegree
        stepFieldsPerDegree = plan.stepFieldsPerDegree
        // From the start end toward the other.
        direction = plan.legStartsHigh ? -1 : 1
    }

    /// The end of `servo`'s range: the high one or the low one.
    private func rangeEnd(of servo: StageAxis, high: Bool) -> Int {
        let range = limits.range(of: servo)
        return high ? range.upperBound : range.lowerBound
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
        defer { updateProgress(angles) }
        if checkFirstColumn(angles) {
            progress = StageZigzagProgress()
            return queue.removeFirst()
        }
        if !started {
            started = true
            approach(angles)
        }
        if let event { handle(event, angles) }
        return queue.isEmpty ? nil : queue.removeFirst()
    }

    // MARK: Progress

    /// By degrees: the columns behind are the step servo's way across, and the current column
    /// counts for the share of its leg that is walked. An estimate, as a column's width varies
    /// with the picture; an edge can also end the path early.
    private mutating func updateProgress(_ angles: (x: Int, y: Int)) {
        guard !isFinished else {
            progress.fraction = 1
            progress.totalColumns = column
            return
        }
        guard column > 0 else { return }
        let far = rangeEnd(of: plan.stepServo, high: !plan.stepStartsHigh)
        let start = rangeEnd(of: plan.stepServo, high: plan.stepStartsHigh)
        // A column step is made of whole moves; from column 3 on, the steps so far say more.
        let chunk = Double(chunkDegrees)
        var width = (Double(columnFallbackDegrees) / chunk).rounded(.up) * chunk
        // Between columns the step counts as the finished column's own share.
        let crossing = stage == .stepMove
        let across = crossing ? anchorAngle : angle(of: plan.stepServo, angles)
        let left = Double(abs(far - across))
        let sofar = abs(across - start)
        if column >= 3, sofar > 0 { width = Double(sofar) / Double(column - 1) }
        var walked = 1.0
        if !crossing {
            let range = bounds()
            let leg = angle(of: plan.legServo, angles)
            let span = max(range.high - range.low, 1)
            let done = direction > 0 ? leg - range.low : range.high - leg
            walked = min(max(Double(done) / Double(span), 0), 1)
        }
        let columnsLeft = (left / width).rounded(.up)
        let total = Double(column) + columnsLeft
        progress.column = column
        progress.totalColumns = Int(total)
        let fraction = (Double(column - 1) + walked) / total
        progress.fraction = min(max(progress.fraction, fraction), 0.99)
    }

    // MARK: First-column direction check

    /// During column 1, once the picture has moved a field, compare its horizontal and vertical
    /// travel: columns that run sideways mean the leg servo is the wrong one. Swaps the roles
    /// (at most once per run) and starts again. True when it did.
    private mutating func checkFirstColumn(_ angles: (x: Int, y: Int)) -> Bool {
        guard swapCheckOpen, column == 1, stage == .legDwell || stage == .legMove else {
            if column > 1 { swapCheckOpen = false }
            return false
        }
        guard let tracked else {
            if swapAnchor != nil { swapCheckOpen = false }  // lost before a field: no check
            return false
        }
        guard let anchor = swapAnchor else {
            swapAnchor = tracked
            return false
        }
        let dx = Double(tracked.x - anchor.x)
        let dy = Double(tracked.y - anchor.y)
        guard hypot(dx, dy) >= Self.swapCheckFields else { return false }
        swapCheckOpen = false
        guard abs(dx) > abs(dy), let mapping,
            let swapped = StageZigzagPlan(mapping: mapping, swappingRoles: !plan.rolesSwapped)
        else { return false }
        let ended = column
        plan = swapped
        legFieldsPerDegree = swapped.legFieldsPerDegree
        stepFieldsPerDegree = swapped.stepFieldsPerDegree
        direction = swapped.legStartsHigh ? -1 : 1
        column = 0
        spot = 0
        lowEdge = nil
        highEdge = nil
        queue = [.swapped(dx: dx, dy: dy), .columnEnded(ended)]
        started = true
        approach(angles)
        return true
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
    private func stepToward(_ end: Int, from current: Int, servo: StageAxis) -> Int {
        let chunk = chunkDegrees + (servo == plan.legServo ? boostLeg : boostStep)
        return current + max(-chunk, min(chunk, end - current))
    }

    private mutating func approach(_ angles: (x: Int, y: Int)) {
        let legEnd = rangeEnd(of: plan.legServo, high: plan.legStartsHigh)
        let stepEnd = rangeEnd(of: plan.stepServo, high: plan.stepStartsHigh)
        let leg = angle(of: plan.legServo, angles)
        let step = angle(of: plan.stepServo, angles)
        if leg != legEnd {
            stage = .approachLeg
            queue.append(
                .moveTo(servo: plan.legServo, angle: stepToward(legEnd, from: leg, servo: plan.legServo)))
        } else if step != stepEnd {
            stage = .approachStep
            queue.append(
                .moveTo(
                    servo: plan.stepServo, angle: stepToward(stepEnd, from: step, servo: plan.stepServo)))
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
        let range = limits.range(of: plan.legServo)
        let low = lowEdge.map { max($0 - plan.rangeMargin, range.lowerBound) } ?? range.lowerBound
        let high = highEdge.map { min($0 + plan.rangeMargin, range.upperBound) } ?? range.upperBound
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
        // Limits narrowed to behind the servo end the leg too, instead of walking it back.
        guard (end - current) * direction > 0 else { return endLeg(angles) }
        let target = stepToward(end, from: current, servo: plan.legServo)
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
        let far = rangeEnd(of: plan.stepServo, high: !plan.stepStartsHigh)
        guard current != far else {
            stage = .done
            isFinished = true
            queue.append(.finished("end of range"))
            return
        }
        stage = .stepMove
        anchorPosition = tracked
        anchorAngle = current
        queue.append(
            .moveTo(servo: plan.stepServo, angle: stepToward(far, from: current, servo: plan.stepServo)))
    }

    /// After a settled step of the column move: next column once the picture has moved a
    /// column's width (or the degree fallback, capped at twice that), else another step.
    private mutating func stepStep(_ angles: (x: Int, y: Int)) {
        let current = angle(of: plan.stepServo, angles)
        let far = rangeEnd(of: plan.stepServo, high: !plan.stepStartsHigh)
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
        queue.append(
            .moveTo(servo: plan.stepServo, angle: stepToward(far, from: current, servo: plan.stepServo)))
    }
}
