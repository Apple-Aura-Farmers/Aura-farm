import CoreGraphics
import Foundation

/// The numbers `GuideOverlayModel.make` decides with. Data, not logic. All PLACEHOLDER: not
/// calibrated; chosen by eye for a phone-sized preview.
struct GuideOverlayThresholds {
    /// How far inside the field's edge an arrow is pinned, and the margin a cross needs to be
    /// drawn rather than pinned, in points.
    var pinMarginPoints: Double = 14
    var arrowLengthPoints: Double = 44
    /// Where a travel instruction's virtual target sits along its direction, in fields.
    var travelArrowFields: Double = 1.5
    /// A go-back vector shorter than this is only a direction, in fields.
    var minimumVectorFields: Double = 0.1
}

enum GuideTone: Equatable { case move, onTarget, wrongWay, warning }

/// What to draw for the target, in screen points.
enum GuideMark: Equatable {
    /// A target cross on the picture.
    case cross(at: CGPoint, tone: GuideTone)
    /// An arrow pinned inside the edge of the field, pointing outward toward the target.
    /// `angle` is in radians on screen (0 points right, positive turns clockwise, as y is down).
    case pinnedArrow(at: CGPoint, angle: Double, tone: GuideTone, distanceFields: Double?)
    case none
}

/// What to draw for one `GuideStep`, in screen points. No SwiftUI, so the capture screen can
/// reuse it.
struct GuideOverlayModel: Equatable {
    /// The box centre on screen.
    var centre: CGPoint
    /// The "on target" zone around the centre.
    var toleranceRadius: Double
    var mark: GuideMark
    /// 0...1 while holding still on a spot.
    var holdProgress: Double?
    var justCaptured: Bool
    /// The helper wording, which only refers to what is drawn.
    var line: String
    var isFinished: Bool
    /// The edge of the sample reached the centre on this reading.
    var justReachedEdge = false
    /// 0...1 while the edge is being checked (the white ring).
    var checkProgress: Double?

    /// - Parameters:
    ///   - step: the guide's answer for this reading.
    ///   - position: where the view is, in the guide's screen fields; `step.target` is in the
    ///     same space.
    ///   - tracking: while paused or matching the position is frozen while the specimen still
    ///     moves, so a cross would sit still on a moving picture: only an arrow is drawn.
    ///   - heading: where the view is being sent, for the arrow of an instruction that has no
    ///     target of its own (checking the edge, refocus while travelling).
    ///   - centre: the box centre on screen, in points.
    ///   - fieldRadius: the radius of the field on screen, in points.
    static func make(
        step: GuideStep, position: CGPoint, tracking: TrackingState, centre: CGPoint,
        pointsPerField: Double, fieldRadius: Double, alignToleranceFields: Double,
        heading: CGPoint? = nil,
        thresholds: GuideOverlayThresholds = GuideOverlayThresholds()
    ) -> GuideOverlayModel {
        var holdProgress: Double?
        if case .holding(let progress) = step.instruction { holdProgress = min(max(progress, 0), 1) }
        var justCaptured = false
        if case .captured = step.instruction { justCaptured = true }
        var justReachedEdge = false
        if case .edgeReached = step.instruction { justReachedEdge = true }
        var checkProgress: Double?
        if case .checkingEdge(let progress) = step.instruction {
            checkProgress = min(max(progress, 0), 1)
        }
        return GuideOverlayModel(
            centre: centre, toleranceRadius: alignToleranceFields * pointsPerField,
            mark: mark(
                step: step, position: position, tracking: tracking, centre: centre,
                pointsPerField: pointsPerField, fieldRadius: fieldRadius, heading: heading,
                thresholds: thresholds),
            holdProgress: holdProgress, justCaptured: justCaptured,
            line: step.instruction.helperText(fullCoverSlip: step.edge.edgeMode == "line"),
            isFinished: step.isFinished,
            justReachedEdge: justReachedEdge, checkProgress: checkProgress)
    }

    static func tone(of instruction: GuideInstruction) -> GuideTone {
        switch instruction {
        case .aligned, .holding: .onTarget
        case .paused, .stageLimit: .warning
        case .tooFar, .otherWay: .wrongWay
        case .slowDown, .refocus: .warning
        default: .move
        }
    }

    private static func mark(
        step: GuideStep, position: CGPoint, tracking: TrackingState, centre: CGPoint,
        pointsPerField: Double, fieldRadius: Double, heading: CGPoint?,
        thresholds: GuideOverlayThresholds
    ) -> GuideMark {
        // The vector to where the picture should go, in fields, and whether it must be an arrow.
        var vector: CGPoint
        var forcesArrow = false
        var hasDistance = true
        switch step.instruction {
        case .paused:
            // The picture is not where the route thinks: nothing to point at.
            return .none
        case .travel(let direction):
            vector = CGPoint(
                x: direction.x * thresholds.travelArrowFields,
                y: direction.y * thresholds.travelArrowFields)
            forcesArrow = true
            hasDistance = false
        case .edgeGoBack(let toward), .stillNoDetail(let toward), .checkEdge(let toward):
            vector = toward
            hasDistance = false
        case .checkingEdge, .refocus, .lineAhead:
            if let target = step.target {
                vector = CGPoint(x: target.x - position.x, y: target.y - position.y)
            } else if let heading {
                // No target of its own: the arrow stays as it was while travelling.
                vector = CGPoint(
                    x: heading.x * thresholds.travelArrowFields,
                    y: heading.y * thresholds.travelArrowFields)
                forcesArrow = true
                hasDistance = false
            } else {
                return .none
            }
        default:
            guard let target = step.target else { return .none }
            vector = CGPoint(x: target.x - position.x, y: target.y - position.y)
        }
        let fields = hypot(Double(vector.x), Double(vector.y))
        guard fields > 1e-9 else { return .none }

        let tone = tone(of: step.instruction)
        let points = CGPoint(
            x: Double(vector.x) * pointsPerField, y: Double(vector.y) * pointsPerField)
        let length = fields * pointsPerField
        let steady = tracking == .tracking
        if steady, !forcesArrow, length + thresholds.pinMarginPoints <= fieldRadius {
            return .cross(at: CGPoint(x: centre.x + points.x, y: centre.y + points.y), tone: tone)
        }
        let pinRadius = max(fieldRadius - thresholds.pinMarginPoints, 0)
        let at = CGPoint(
            x: Double(centre.x) + Double(points.x) / length * pinRadius,
            y: Double(centre.y) + Double(points.y) / length * pinRadius)
        return .pinnedArrow(
            at: at, angle: atan2(Double(points.y), Double(points.x)), tone: tone,
            distanceFields: hasDistance ? fields : nil)
    }
}
