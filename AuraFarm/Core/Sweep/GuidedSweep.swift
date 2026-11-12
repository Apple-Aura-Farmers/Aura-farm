import CoreGraphics
import Foundation

/// What the guide says after one reading.
struct GuideStep: Equatable {
    var instruction: GuideInstruction
    var target: CGPoint?
    /// Set only on the reading where a capture happens.
    var capture: FramePlacement?
    /// A short name for the route state, for the lab and the CSV, for example "column 3 down".
    var stateName: String
    var column: Int
    var isFinished: Bool
    var finishReason: SweepFinishReason?
}

/// Tells a person moving a slide by hand where to go next, so the whole sample is covered
/// with the least travel and no trip across blank glass. This is the one type the caller uses.
///
/// Coordinates, for everything in the guide:
/// - Positions are in FIELDS (1 field = the registration box side) in SCREEN axes: x to the
///   right, y down, as `ScreenMapping.onScreen` returns.
/// - A position is where the VIEW has travelled across the slide (`HopOdometer`'s
///   convention, mapped to the screen). "Left edge" means the view travels left until the
///   sample ends.
/// - The caller converts odometer px to screen fields (the lab uses `ScreenMapping.onScreen`
///   with its mapping and mirror, divided by the box side). The guide never sees pixels,
///   Vision or camera types.
/// - The guide is deterministic: time comes in as seconds on each reading.
///
/// See `SlideRoute` for the route and its known limitation.
struct GuidedSweep {
    private var route: SlideRoute

    init(thresholds: GuidedSweepThresholds = GuidedSweepThresholds()) {
        route = SlideRoute(thresholds: thresholds)
    }

    var placements: [FramePlacement] { route.placements }
    var isFinished: Bool { route.isFinished }
    var finishReason: SweepFinishReason? { route.finishReason }
    /// Times the left edge was looked for again, and steps right that landed on blank. For
    /// the lab and the tests.
    var rechecks: Int { route.rechecks }
    var failedProbes: Int { route.failedProbes }

    mutating func update(_ reading: GuideReading) -> GuideStep {
        let output = route.update(reading)
        return GuideStep(
            instruction: route.isFinished ? .finished : output.instruction, target: output.target,
            capture: output.capture, stateName: route.stateName, column: route.columnNumber,
            isFinished: route.isFinished, finishReason: route.finishReason)
    }

    /// Ends the route at once, whatever it was doing. The instruction is then always
    /// `.finished`.
    mutating func finish(reason: SweepFinishReason) {
        route.finish(reason: reason)
    }
}
