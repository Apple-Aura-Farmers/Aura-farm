#if DEBUG
    import CoreGraphics
    import Foundation

    /// The guide's columns in the CSV for one row.
    struct GuideRowFields: Equatable {
        var viewClass: String
        var state: String
        var instruction: String
        var targetDx: Double?
        var targetDy: Double?
        var captures: Int
        /// The manual mapping the axes in use are nearest to: "rotateLeft", "asIs-mirrored", ...
        var axesMapping = ""
    }

    /// How the preview shows the box, measured from the live preview layer on the main thread.
    struct GuideScreenGeometry: Equatable {
        var axes: GuideScreenAxes
        /// The box centre on screen, in points.
        var centre: CGPoint
        /// The box's on-screen side, in points: one field.
        var pointsPerField: Double
        /// The radius of the field on screen, in points; arrows are pinned just inside it.
        var fieldRadius: Double
    }

    /// What one guide update gives the lab.
    struct GuideDryRunResult {
        var fields: GuideRowFields
        var info: SlideMovementInfo.Guide
        /// nil without a preview to draw on (a recorded video).
        var overlay: GuideOverlayModel?
        /// A capture and the target, in the trail's space (frame axes, in fields).
        var captureTrailPoint: CGPoint?
        var targetTrailPoint: CGPoint?
    }

    /// Feeds `ViewClassifier` and `GuidedSweep` from the lab's steps, so the team can try the
    /// guide on the microscope before it has a screen of its own. Nothing is saved as a sweep
    /// and no frames are written. Analysis queue only.
    ///
    /// The tracker's position is the content's displacement, so the guide's position (where the
    /// VIEW is) is its negation through the axes of the content's motion on screen.
    final class GuideDryRun {
        /// How the lab shows the frame's axes on screen, from the picker. Used only when there
        /// is no preview geometry to measure the axes from.
        var mapping = ScreenMapping.asIs
        var mirrored = false
        var geometry: GuideScreenGeometry?

        private var classifier = ViewClassifier()
        private var guide = GuidedSweep()
        private let alignTolerance = GuidedSweepThresholds().alignment.alignToleranceFields
        private(set) var captureCount = 0
        private(set) var edgeCount = 0
        private(set) var wrongWayCount = 0
        private(set) var edgeReachedCount = 0
        private var lastInstruction: GuideInstruction?
        /// Where the guide last sent the view (a screen unit vector), to work out which half of
        /// the box the next content comes into.
        private var lastHeading: CGPoint?

        /// Feeds one lab step; returns the CSV fields and the info for the screen.
        func update(
            step: SlideMovementStep, indicators: MovementIndicators, seconds: Double
        ) -> GuideDryRunResult {
            let viewClass = classifier.update(
                brightness: step.boxStats.brightness, sharpness: step.boxStats.sharpness,
                contrast: step.boxStats.contrast)

            // The position in screen fields: the tracker's pixels through the axes, divided by
            // the on-screen size of one field. Without a preview the picker's mapping stands in,
            // with a field being the box's side in pixels.
            let boxSide = max(step.boxSide, 1)
            // The axes of the CONTENT's motion on screen: measured from the preview, or the
            // picker's mapping (which describes the view's travel) negated.
            let axes =
                geometry?.axes
                ?? GuideScreenAxes.from(mapping, mirrored: mirrored, pointsPerPixel: 1).viewTravel
            let pointsPerField = geometry?.pointsPerField ?? boxSide
            let position = axes.guideFields(
                forTrackerPosition: step.position, pointsPerField: pointsPerField)
            let tracking = step.tracking.trackingState

            // The half of the box the view is travelling toward. `axes` map a frame vector to the
            // screen, so the frame direction that shows as the heading is its inverse; new
            // content comes into view on that side of the box.
            var ahead: Double?
            var behind: Double?
            if let heading = lastHeading, let halves = step.tracking.halfSharpness,
                let frameDirection = axes.frameVector(ofScreenVector: heading),
                let pair = halves.aheadAndBehind(forFrameDirection: frameDirection)
            {
                (ahead, behind) = (pair.ahead, pair.behind)
            }
            var aheadFocus: Double?
            var behindFocus: Double?
            if let heading = lastHeading, let ratios = step.tracking.halfFocusRatio,
                let frameDirection = axes.frameVector(ofScreenVector: heading),
                let pair = ratios.aheadAndBehind(forFrameDirection: frameDirection)
            {
                (aheadFocus, behindFocus) = (pair.ahead, pair.behind)
            }
            let result = guide.update(
                GuideReading(
                    seconds: seconds, position: position, tracking: tracking,
                    unconfirmedGaps: step.tracking.unconfirmedGaps, viewClass: viewClass,
                    speedFraction: indicators.speedFraction, isStill: indicators.stillSeconds > 0,
                    aheadSharpness: ahead, behindSharpness: behind, aheadFocusRatio: aheadFocus,
                    behindFocusRatio: behindFocus))
            lastHeading = guide.heading
            if case .edgeReached = result.instruction { edgeReachedCount += 1 }

            if result.capture != nil { captureCount += 1 }
            if case .edgeGoBack = result.instruction {
                if case .edgeGoBack? = lastInstruction {} else { edgeCount += 1 }
            }
            if Self.isWrongWay(result.instruction), !Self.isWrongWay(lastInstruction) {
                wrongWayCount += 1
            }
            lastInstruction = result.instruction

            let dx = result.target.map { Double($0.x - position.x) }
            let dy = result.target.map { Double($0.y - position.y) }
            let captures = guide.placements.count

            // The picker describes how the VIEW's travel appears on screen: compare with that.
            let closest = axes.viewTravel.closestMapping()
            let axesMapping = closest.mapping.rawValue + (closest.mirrored ? "-mirrored" : "")
            var axesLine = ""
            if geometry != nil {
                axesLine =
                    "Axes from preview match: \(closest.mapping.title)"
                    + (closest.mirrored ? ", mirrored" : "")
            }
            let differs = geometry != nil && (closest.mapping != mapping || closest.mirrored != mirrored)

            var overlay: GuideOverlayModel?
            if let geometry {
                overlay = GuideOverlayModel.make(
                    step: result, position: position, tracking: tracking, centre: geometry.centre,
                    pointsPerField: pointsPerField, fieldRadius: geometry.fieldRadius,
                    alignToleranceFields: alignTolerance, heading: guide.heading ?? lastHeading)
            }
            var targetPoint: CGPoint?
            if let target = result.target,
                let frame = axes.frameVector(
                    ofScreenVector: CGPoint(
                        x: Double(target.x - position.x) * pointsPerField,
                        y: Double(target.y - position.y) * pointsPerField))
            {
                // Back into the tracker's space (content displacement): the view travels the
                // opposite way, so the offset is subtracted.
                targetPoint = CGPoint(
                    x: step.positionFields.x - frame.x / boxSide,
                    y: step.positionFields.y - frame.y / boxSide)
            }
            return GuideDryRunResult(
                fields: GuideRowFields(
                    viewClass: viewClass.rawValue, state: result.stateName,
                    instruction: result.instruction.csvName, targetDx: dx, targetDy: dy,
                    captures: captures, axesMapping: axesMapping),
                info: SlideMovementInfo.Guide(
                    isOn: true, instruction: result.instruction.debugText, state: result.stateName,
                    targetDx: dx, targetDy: dy, viewClass: viewClass.rawValue, captures: captures,
                    captureCount: captureCount, edgeCount: edgeCount, isFinished: result.isFinished,
                    wrongWayCount: wrongWayCount, edgeReachedCount: edgeReachedCount, axesLine: axesLine,
                    axesDiffer: differs),
                overlay: overlay,
                captureTrailPoint: result.capture == nil ? nil : step.positionFields,
                targetTrailPoint: targetPoint)
        }

        private static func isWrongWay(_ instruction: GuideInstruction?) -> Bool {
            switch instruction {
            case .tooFar?, .otherWay?: true
            default: false
            }
        }

        func reset() {
            classifier.reset()
            guide = GuidedSweep()
            captureCount = 0
            edgeCount = 0
            wrongWayCount = 0
            edgeReachedCount = 0
            lastHeading = nil
            lastInstruction = nil
        }
    }
#endif
