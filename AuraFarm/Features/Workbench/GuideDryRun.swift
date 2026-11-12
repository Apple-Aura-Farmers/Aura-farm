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
    }

    /// Feeds `ViewClassifier` and `GuidedSweep` from the lab's steps, so the team can try the
    /// guide on the microscope before it has a screen of its own. Nothing is saved as a sweep
    /// and no frames are written. Analysis queue only.
    final class GuideDryRun {
        /// How the lab shows the frame's axes on screen; the guide works in screen axes.
        var mapping = ScreenMapping.asIs
        var mirrored = false

        private var classifier = ViewClassifier()
        private var guide = GuidedSweep()
        private(set) var captureCount = 0
        private(set) var edgeCount = 0
        private var lastInstruction: GuideInstruction?

        /// Feeds one lab step; returns the CSV fields and the info for the screen.
        func update(
            step: SlideMovementStep, indicators: MovementIndicators, seconds: Double
        ) -> (fields: GuideRowFields, info: SlideMovementInfo.Guide) {
            let viewClass = classifier.update(
                brightness: step.boxStats.brightness, sharpness: step.boxStats.sharpness,
                contrast: step.boxStats.contrast)

            let tracking: TrackingState
            if !step.hasDetail {
                tracking = .paused
            } else if step.reading == "matching" {
                tracking = .matching
            } else if step.isLost {
                tracking = .lost
            } else {
                tracking = .tracking
            }

            let onScreen = mapping.onScreen(step.position, mirrored: mirrored)
            let side = max(step.boxSide, 1)
            let position = CGPoint(x: onScreen.x / side, y: onScreen.y / side)
            let result = guide.update(
                GuideReading(
                    seconds: seconds, position: position, tracking: tracking,
                    unconfirmedGaps: step.blankReturnsUnmatched + step.gaps, viewClass: viewClass,
                    speedFraction: indicators.speedFraction, isStill: indicators.stillSeconds > 0))

            if result.capture != nil { captureCount += 1 }
            if case .edgeGoBack = result.instruction {
                if case .edgeGoBack? = lastInstruction {} else { edgeCount += 1 }
            }
            lastInstruction = result.instruction

            let dx = result.target.map { Double($0.x - position.x) }
            let dy = result.target.map { Double($0.y - position.y) }
            let captures = guide.placements.count
            return (
                GuideRowFields(
                    viewClass: viewClass.rawValue, state: result.stateName,
                    instruction: result.instruction.csvName, targetDx: dx, targetDy: dy,
                    captures: captures),
                SlideMovementInfo.Guide(
                    isOn: true, instruction: result.instruction.debugText, state: result.stateName,
                    targetDx: dx, targetDy: dy, viewClass: viewClass.rawValue, captures: captures,
                    captureCount: captureCount, edgeCount: edgeCount, isFinished: result.isFinished)
            )
        }

        func reset() {
            classifier.reset()
            guide = GuidedSweep()
            captureCount = 0
            edgeCount = 0
            lastInstruction = nil
        }
    }
#endif
