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
    /// What the edge conditions made of this reading, for the CSV.
    var edge = EdgeDiagnostics()
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
    /// Edges found with the edge at the centre of the view, and by going past it and back
    /// (left edge and leg ends only). For the lab and the tests.
    var edgesReached: Int { route.edgesReached }
    var edgesGoneBack: Int { route.edgesGoneBack }
    /// The direction the VIEW is being sent, as a screen unit vector, while travelling to the
    /// left edge, sweeping a column leg or stepping right; nil in the other phases.
    var heading: CGPoint? { route.guideHeading }

    /// The direction an edge line is looked for along (screen unit vector): the left-edge run, a
    /// column leg or a step right; nil otherwise. See `SlideRoute.edgeHeading`.
    var edgeHeading: CGPoint? { route.edgeHeading }

    /// Why the run is paused, nil while it runs.
    private(set) var pauseReason: GuidePauseReason?
    /// When the last pause ended, in the readings' seconds.
    private(set) var resumedAt: Double?
    private var lastTarget: CGPoint?
    /// The limits the helper recorded with `stageLimitReached`, kept for every later column.
    var stageLimits: SlideRoute.StageLimits { route.limits }

    mutating func update(_ reading: GuideReading) -> GuideStep {
        if let pauseReason, !route.isFinished {
            // Paused: the route is not fed, so nothing is captured, confirmed or timed. The
            // tracker keeps running outside, so the position stays right.
            return GuideStep(
                instruction: .paused(pauseReason), target: lastTarget, capture: nil,
                stateName: "paused", column: route.columnNumber, isFinished: false,
                finishReason: nil)
        }
        return step(from: route.update(reading))
    }

    /// The helper says the stage cannot go further: the limit is recorded and the route turns
    /// as at an edge (see `SlideRoute.stageLimitReached`). Ignored while paused.
    mutating func stageLimitReached(_ reading: GuideReading) -> GuideStep {
        guard pauseReason == nil else { return update(reading) }
        return step(from: route.stageLimitReached(reading))
    }

    /// The helper's answer to an edge in full-cover-slip mode (see `SlideRoute.userEdge`). Ignored
    /// while paused.
    mutating func userEdge(_ feedback: EdgeFeedback, _ reading: GuideReading) -> GuideStep {
        guard pauseReason == nil else { return update(reading) }
        return step(from: route.userEdge(feedback, reading))
    }

    /// Holds the route where it is until `resume`.
    mutating func pause(_ reason: GuidePauseReason) {
        pauseReason = reason
    }

    /// Carries on, with every timer of the route cleared so nothing fires because of the gap:
    /// a fresh low-detail stretch is needed before any edge.
    mutating func resume(seconds: Double) {
        guard pauseReason != nil else { return }
        pauseReason = nil
        resumedAt = seconds
        route.clearTimers()
    }

    private mutating func step(from output: SlideRoute.Output) -> GuideStep {
        lastTarget = output.target ?? lastTarget
        return GuideStep(
            instruction: route.isFinished ? .finished : output.instruction, target: output.target,
            capture: output.capture, stateName: route.stateName, column: route.columnNumber,
            isFinished: route.isFinished, finishReason: route.finishReason,
            edge: route.diagnostics)
    }

    /// Ends the route at once, whatever it was doing. The instruction is then always
    /// `.finished`.
    mutating func finish(reason: SweepFinishReason) {
        route.finish(reason: reason)
    }
}
