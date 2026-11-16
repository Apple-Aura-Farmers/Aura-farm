import CoreGraphics
import Foundation

@testable import AuraFarm

/// A simulated drop: sample inside the circles, blank outside (and inside the holes).
struct SimulatedDrop {
    var circles: [(centre: CGPoint, radius: Double)]
    var holes: [(centre: CGPoint, radius: Double)] = []
    /// Square or rectangular sample, like a cover slip filled with sample.
    var rects: [CGRect] = []
    /// The rectangles are turned by this angle (radians) about the middle of the first one: a
    /// cover slip whose edges are not parallel to the stage's axes.
    var rotation = 0.0

    /// A square cover slip turned by `degrees` against the stage axes.
    static func skewedSquare(from origin: CGPoint, side: Double, degrees: Double) -> SimulatedDrop {
        var drop = square(from: origin, side: side)
        drop.rotation = degrees * .pi / 180
        return drop
    }

    private var pivot: CGPoint {
        rects.first.map { CGPoint(x: $0.midX, y: $0.midY) } ?? .zero
    }

    /// `point` in the rectangles' own, unturned axes.
    private func unturned(_ point: CGPoint) -> CGPoint {
        guard rotation != 0 else { return point }
        let dx = Double(point.x - pivot.x)
        let dy = Double(point.y - pivot.y)
        return CGPoint(
            x: Double(pivot.x) + cos(rotation) * dx + sin(rotation) * dy,
            y: Double(pivot.y) - sin(rotation) * dx + cos(rotation) * dy)
    }

    /// The rectangle's corners as the stage sees them (turned).
    private func corners(of rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
        ].map { corner in
            let dx = Double(corner.x - pivot.x)
            let dy = Double(corner.y - pivot.y)
            return CGPoint(
                x: Double(pivot.x) + cos(rotation) * dx - sin(rotation) * dy,
                y: Double(pivot.y) + sin(rotation) * dx + cos(rotation) * dy)
        }
    }

    /// A sample that fills a rectangle.
    static func square(from origin: CGPoint, side: Double) -> SimulatedDrop {
        SimulatedDrop(circles: [], rects: [CGRect(x: origin.x, y: origin.y, width: side, height: side)])
    }

    func contains(_ point: CGPoint) -> Bool {
        let inside =
            circles.contains {
                hypot(Double(point.x - $0.centre.x), Double(point.y - $0.centre.y)) <= $0.radius
            } || rects.contains { $0.contains(unturned(point)) }
        let hole = holes.contains {
            hypot(Double(point.x - $0.centre.x), Double(point.y - $0.centre.y)) <= $0.radius
        }
        return inside && !hole
    }

    /// The middle of the sample: the mean of its circles' centres and rectangles' middles.
    var centre: CGPoint? {
        let points =
            circles.map(\.centre) + rects.map { CGPoint(x: $0.midX, y: $0.midY) }
        guard !points.isEmpty else { return nil }
        let count = CGFloat(points.count)
        return CGPoint(
            x: points.reduce(0) { $0 + $1.x } / count, y: points.reduce(0) { $0 + $1.y } / count)
    }

    /// Whether the point is just outside the sample, within `width` of its edge (probed in 8
    /// directions): where half the box is over sample and half over glass.
    func isJustOutside(_ point: CGPoint, width: Double) -> Bool {
        guard !contains(point) else { return false }
        return (0..<8).contains { index in
            let angle = Double(index) * .pi / 4
            return contains(
                CGPoint(
                    x: point.x + CGFloat(cos(angle) * width), y: point.y + CGFloat(sin(angle) * width)))
        }
    }

    /// Points on a 0.2 field grid inside the drop.
    func gridPoints(step: Double = 0.2) -> [CGPoint] {
        let xs =
            circles.flatMap { [Double($0.centre.x) - $0.radius, Double($0.centre.x) + $0.radius] }
            + rects.flatMap { rect in corners(of: rect).map { Double($0.x) } }
        let ys =
            circles.flatMap { [Double($0.centre.y) - $0.radius, Double($0.centre.y) + $0.radius] }
            + rects.flatMap { rect in corners(of: rect).map { Double($0.y) } }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return []
        }
        var points: [CGPoint] = []
        var y = minY
        while y <= maxY {
            var x = minX
            while x <= maxX {
                let point = CGPoint(x: x, y: y)
                if contains(point) { points.append(point) }
                x += step
            }
            y += step
        }
        return points
    }
}

/// A helper who follows the guide's instructions, 10 readings a second, 0.1 field a reading.
/// While the view is over blank glass the tracker is paused and its position frozen; when the
/// view comes back onto sample within 0.4 field of where it paused, the true position returns
/// (a matched return), otherwise the position resumes from the frozen one plus an error and
/// `unconfirmedGaps` rises.
final class GuideSimulator {
    struct Result {
        var readings: Int
        var finished: Bool
        var finishReason: SweepFinishReason?
        var placements: [FramePlacement]
        /// The true position at each capture.
        var capturedTruth: [CGPoint]
        var instructions: [GuideInstruction]
        var states: [String]
        var coverage: Double
        var rechecks: Int
        var failedProbes: Int
        /// Left edge and leg-end edges found with the edge at the centre, and by going back.
        var edgesReached: Int
        var edgesGoneBack: Int
        /// Edges fired with no edge near the true position, and those within 3 s of an injected
        /// knock: false edges.
        var falseEdges = 0
        var falseEdgesNearKnocks = 0
        var knocks = 0
    }

    let drop: SimulatedDrop
    var guide = GuidedSweep()
    var truePosition: CGPoint
    /// What the tracker adds to the true position; changes after an unmatched return.
    private var bias = CGPoint.zero
    private var frozen: CGPoint
    private var paused = false
    private var pauseTruth: CGPoint?
    private var lastSampleTruth: CGPoint?
    private var unconfirmed = 0
    private var returnCount = 0
    private var lastReturn = BlankReturnOutcome.none
    private var seconds = 0.0
    private var lastMove = 0.0
    private var pending: CGPoint = .zero

    /// The error a position picks up on an unmatched return; nil means returns are matched
    /// whatever the distance.
    var unmatchedError: CGPoint?
    /// Head the wrong way for this many fields at the first move after the first capture.
    var wrongWayFields = 0.0
    /// Go on this far past a spot the first time one is reached.
    var overshootFields = 0.0
    /// The overshoot is made at the first spot approached after this many captures.
    var overshootAfterCaptures = 12
    /// Readings (by index) at which the tracker reports `.lost` for 5 readings.
    var lostAtReading: Int?
    var lostRaisesGap = false
    /// Soil slide: the glass outside the sample is as bright as the sample, so it reads blurry
    /// (not blank) with tracking paused, and an edge band flickers (see `edgeBandFields`).
    var soil = false
    /// The width of the flickering band just outside the edge, in fields (soil only).
    var edgeBandFields = 0.3
    /// In the band: low detail for this long, then detail for `bandDetailSeconds`, repeating.
    var bandLowSeconds = 0.6
    var bandDetailSeconds = 0.4
    /// Soil only: a flicker of low detail of 0.3 s starts at random about this often inside
    /// the sample (readings between flickers on average); nil for none. Seeded, so repeatable.
    var interiorFlickerEveryReadings: Int?
    private var randomState: UInt64 = 7
    private var interiorLowLeft = 0
    /// A helper who stops as soon as the edge reaches the centre of the view (the half ahead
    /// has no detail, the half behind does) while heading for an edge or along a column leg,
    /// as a person watching the picture would.
    var stopsAtEdge = true
    /// Random knocks about every 20 s: a flick (a speed spike, then 3 to 5 blurred readings) or
    /// a focus slip (2 s of blur while the helper holds still). Seeded, so repeatable.
    var knocks = false
    private var knockState: UInt64 = 99
    private var blurLeft = 0
    private var blurShown = 0
    private var slipActive = false
    private var spikeNext = false
    private var knockStarts: [Int] = []
    private let sharpOnBlur = 50.0
    private var heading: CGPoint?
    private var edgeAtCentre = false
    private var lastTracking = TrackingState.tracking
    private var goBackReadings = 0
    private var stoppedAtEdge = 0
    /// The sharpness the simulated halves read with and without sample.
    private let sharpOnSample = 400.0
    private let sharpOnGlass = 50.0
    /// Where a helper who starts on blank heads to.
    var searchTarget = CGPoint.zero
    private var wrongWayLeft = 0.0
    private var overshootLeft = 0.0
    private var overshotAlready = false
    private var wrongWayDone = false
    private var capturesSoFar = 0
    private let step = 0.1

    init(drop: SimulatedDrop, start: CGPoint) {
        self.drop = drop
        truePosition = start
        frozen = start
    }

    /// Where the guide thinks the view is, and the time of the last reading, to carry on by hand.
    var guidePosition: CGPoint { frozen }
    var guideSeconds: Double { seconds }

    /// - Parameter until: stops the run after the first reading whose answer satisfies it.
    func run(maxReadings: Int = 40000, until: ((GuideStep) -> Bool)? = nil) -> Result {
        var instructions: [GuideInstruction] = []
        var states: [String] = []
        var truths: [CGPoint] = []
        var count = 0
        var falseEdges = 0
        var falseNearKnocks = 0
        var wasGoingBack = false
        wrongWayLeft = wrongWayFields
        while count < maxReadings, !guide.isFinished {
            count += 1
            seconds += 0.1
            let reading = makeReading(index: count)
            let previousHeading = heading
            let output = guide.update(reading)
            heading = guide.heading
            let goingBack = output.stateName == "edge: go back"
            var isEdge = false
            if case .edgeReached = output.instruction { isEdge = true }
            if goingBack, !wasGoingBack { isEdge = true }
            wasGoingBack = goingBack
            if isEdge, !edgeIsNear(previousHeading) {
                falseEdges += 1
                if knockStarts.contains(where: { count - $0 >= 0 && count - $0 <= 30 }) {
                    falseNearKnocks += 1
                }
            }
            instructions.append(output.instruction)
            if states.last != output.stateName { states.append(output.stateName) }
            if output.capture != nil {
                truths.append(truePosition)
                capturesSoFar += 1
            }
            if output.isFinished { break }
            if let until, until(output) { break }
            act(on: output)
        }
        let points = drop.gridPoints()
        let covered = points.filter { point in
            truths.contains { hypot(Double($0.x - point.x), Double($0.y - point.y)) <= 0.6 }
        }.count
        return Result(
            readings: count, finished: guide.isFinished, finishReason: guide.finishReason,
            placements: guide.placements, capturedTruth: truths, instructions: instructions,
            states: states, coverage: points.isEmpty ? 1 : Double(covered) / Double(points.count),
            rechecks: guide.rechecks, failedProbes: guide.failedProbes,
            edgesReached: guide.edgesReached, edgesGoneBack: guide.edgesGoneBack,
            falseEdges: falseEdges, falseEdgesNearKnocks: falseNearKnocks, knocks: knockStarts.count)
    }

    /// Whether the true position is at, past or within 0.6 field ahead of the sample's edge:
    /// an edge fired there is a real one.
    private func edgeIsNear(_ heading: CGPoint?) -> Bool {
        guard drop.contains(truePosition) else { return true }
        let direction = heading ?? CGPoint(x: -1, y: 0)
        let ahead = CGPoint(
            x: truePosition.x + 0.6 * direction.x, y: truePosition.y + 0.6 * direction.y)
        return !drop.contains(ahead)
    }

    private func makeReading(index: Int) -> GuideReading {
        var tracking = TrackingState.tracking
        var viewClass = ViewClass.sample
        if isDetailed() {
            if paused {
                paused = false
                if let origin = pauseTruth,
                    hypot(Double(truePosition.x - origin.x), Double(truePosition.y - origin.y)) > 0.4,
                    let error = unmatchedError
                {
                    unconfirmed += 1
                    returnCount += 1
                    lastReturn = .unmatched
                    bias = CGPoint(
                        x: frozen.x + error.x - truePosition.x, y: frozen.y + error.y - truePosition.y)
                } else if pauseTruth == nil {
                    // Nothing was ever tracked: the position carries on from where it froze.
                    unconfirmed += 1
                    returnCount += 1
                    lastReturn = .unmatched
                    bias = CGPoint(x: frozen.x - truePosition.x, y: frozen.y - truePosition.y)
                } else {
                    returnCount += 1
                    lastReturn = .matched
                }
            }
            lastSampleTruth = truePosition
            frozen = CGPoint(x: truePosition.x + bias.x, y: truePosition.y + bias.y)
        } else {
            if !paused {
                paused = true
                pauseTruth = lastSampleTruth
            }
            tracking = .paused
            viewClass = soil ? .blurry : .blank
        }
        if let lost = lostAtReading, index >= lost, index < lost + 5 {
            tracking = .lost
            if lostRaisesGap, index == lost { unconfirmed += 1 }
        }
        // The halves of the box: half a field from the centre along the heading, and behind it.
        var ahead: Double?
        var behind: Double?
        var sideA: Double?
        var sideB: Double?
        edgeAtCentre = false
        if tracking == .tracking, let heading {
            // The halves across the heading, each as the share of its area over sample (a 4 x 4
            // grid): a stage that is skewed makes one side drift over the cover slip's edge.
            func sideSharpness(_ sign: Double) -> Double {
                var inside = 0
                for along in 0..<4 {
                    for across in 0..<4 {
                        let u = (Double(along) + 0.5) / 4 - 0.5
                        let v = sign * (Double(across) + 0.5) / 8
                        let point = CGPoint(
                            x: truePosition.x + CGFloat(u * Double(heading.x) - v * Double(heading.y)),
                            y: truePosition.y + CGFloat(u * Double(heading.y) + v * Double(heading.x)))
                        if drop.contains(point) { inside += 1 }
                    }
                }
                return sharpOnGlass + (sharpOnSample - sharpOnGlass) * Double(inside) / 16
            }
            sideA = sideSharpness(1)
            sideB = sideSharpness(-1)
            func sharpness(_ sign: Double) -> Double {
                let point = CGPoint(
                    x: truePosition.x + CGFloat(sign * 0.5) * heading.x,
                    y: truePosition.y + CGFloat(sign * 0.5) * heading.y)
                return drop.contains(point) ? sharpOnSample : sharpOnGlass
            }
            ahead = sharpness(1)
            behind = sharpness(-1)
            // The person stops when the edge itself is at the cross, not when it first shows.
            let edge = CGPoint(
                x: truePosition.x + 0.1 * heading.x, y: truePosition.y + 0.1 * heading.y)
            edgeAtCentre = (ahead ?? 0) < 120 && (behind ?? 0) >= 120 && !drop.contains(edge)
        }
        // How sharp each half is against the same content before: 1 when it is the sample.
        var aheadFocus: Double?
        var behindFocus: Double?
        if let ahead, let behind {
            aheadFocus = ahead >= 120 ? 1.0 : 0.2
            // The same patch of content as in the anchor, as sharp as before unless blurred.
            behindFocus = 0.95
        }
        var speed = lastMove / 1.0
        if knocks {
            if blurLeft == 0 {
                knockState = knockState &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                if Int((knockState >> 33) % 200) == 0 {
                    let flick = (knockState >> 20) % 2 == 0
                    blurLeft = flick ? 3 + Int((knockState >> 40) % 3) : 20
                    slipActive = !flick
                    spikeNext = flick
                    blurShown = 0
                    knockStarts.append(index)
                }
            }
            if blurLeft > 0 {
                blurLeft -= 1
                if spikeNext {
                    speed = 0.3
                    spikeNext = false
                }
                blurShown += 1
                if tracking == .tracking {
                    // The tracker takes 3 blurred readings to pause, like `DetailCheck`.
                    if blurShown > 3 { tracking = .paused }
                    viewClass = .blurry
                    (ahead, behind) = (sharpOnBlur, sharpOnBlur)
                    (sideA, sideB) = (sharpOnBlur, sharpOnBlur)
                    (aheadFocus, behindFocus) = (0.3, 0.3)
                }
                if blurLeft == 0 { slipActive = false }
            }
        }
        lastTracking = tracking
        return GuideReading(
            seconds: seconds, position: frozen, tracking: tracking, unconfirmedGaps: unconfirmed,
            viewClass: viewClass, speedFraction: speed, isStill: lastMove == 0,
            aheadSharpness: ahead, behindSharpness: behind, aheadFocusRatio: aheadFocus,
            behindFocusRatio: behindFocus, sideSharpnessA: sideA, sideSharpnessB: sideB,
            lastBlankReturn: lastReturn, blankReturnCount: returnCount)
    }

    /// Whether the view shows enough detail to follow. Over blank glass never; on a soil slide
    /// also not during the low part of an edge-band flicker or an interior flicker.
    private func isDetailed() -> Bool {
        guard drop.contains(truePosition) else {
            // Soil: with the centre just past the edge the box straddles it, and its sharpness
            // hovers about the cut: low for `bandLowSeconds`, detail for `bandDetailSeconds`.
            guard soil, drop.isJustOutside(truePosition, width: edgeBandFields) else { return false }
            let cycle = bandLowSeconds + bandDetailSeconds
            return seconds.truncatingRemainder(dividingBy: cycle) >= bandLowSeconds - 1e-9
        }
        guard soil else { return true }
        if interiorLowLeft > 0 {
            interiorLowLeft -= 1
            return false
        }
        if let every = interiorFlickerEveryReadings {
            randomState = randomState &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            if Int((randomState >> 33) % UInt64(every)) == 0 {
                interiorLowLeft = 2
                return false
            }
        }
        return true
    }

    /// The states where a person heads for an edge: the left edge runs and column legs.
    private static func isEdgeBound(_ state: String) -> Bool {
        state == "find left edge" || state == "recheck left edge"
            || (state.hasPrefix("column") && (state.hasSuffix("up") || state.hasSuffix("down")))
    }

    private func move(_ vector: CGPoint) {
        let length = hypot(Double(vector.x), Double(vector.y))
        guard length > 1e-9 else {
            lastMove = 0
            return
        }
        let distance = min(step, length)
        truePosition = CGPoint(
            x: truePosition.x + CGFloat(Double(vector.x) / length * distance),
            y: truePosition.y + CGFloat(Double(vector.y) / length * distance))
        lastMove = distance
    }

    private func act(on output: GuideStep) {
        switch output.instruction {
        case .edgeGoBack, .stillNoDetail, .checkEdge: break
        default: goBackReadings = 0
        }
        // The helper's own mistakes come first.
        if overshootLeft > 0 {
            overshootLeft -= step
            move(pending)
            return
        }
        if wrongWayLeft > 0, capturesSoFar >= 1, let target = output.target,
            case .move = output.instruction
        {
            wrongWayLeft -= step
            let away = CGPoint(x: frozen.x - target.x, y: frozen.y - target.y)
            move(away)
            return
        }
        if slipActive {
            lastMove = 0
            return
        }
        if stopsAtEdge, edgeAtCentre, Self.isEdgeBound(output.stateName) {
            switch output.instruction {
            case .travel, .move, .farAway:
                // A person who stopped at what looks like the edge but is still told to carry
                // on does so after 2 s.
                stoppedAtEdge += 1
                if stoppedAtEdge <= 20 {
                    lastMove = 0
                    return
                }
            default:
                break
            }
        } else {
            stoppedAtEdge = 0
        }
        switch output.instruction {
        case .findSample:
            move(CGPoint(x: searchTarget.x - truePosition.x, y: searchTarget.y - truePosition.y))
        case .travel(let direction), .farAway(let direction):
            move(direction)
        case .move(let toward):
            let remaining = hypot(Double(toward.x), Double(toward.y))
            if overshootFields > 0, !overshotAlready, capturesSoFar >= overshootAfterCaptures,
                remaining <= 0.25
            {
                overshotAlready = true
                overshootLeft = remaining + overshootFields
                pending = toward
            }
            move(toward)
        case .edgeGoBack(let toward), .stillNoDetail(let toward), .checkEdge(let toward):
            // A person who has not found the sample after 3 s of going back turns toward it.
            goBackReadings += 1
            if goBackReadings > 30, let centre = drop.centre {
                move(CGPoint(x: centre.x - truePosition.x, y: centre.y - truePosition.y))
            } else {
                move(toward)
            }
        case .tooFar, .otherWay:
            if let target = output.target {
                move(CGPoint(x: target.x - frozen.x, y: target.y - frozen.y))
            } else {
                lastMove = 0
            }
        case .checkingEdge:
            // The person stops when the edge itself is at the cross; before that the checking
            // starts while the helper is still on the way there.
            // While the tracker is paused (the whole box is blank) there is nothing to approach.
            if stopsAtEdge, lastTracking == .tracking, !edgeAtCentre, let target = output.target {
                move(CGPoint(x: target.x - frozen.x, y: target.y - frozen.y))
            } else if stopsAtEdge, lastTracking == .tracking, !edgeAtCentre, let heading {
                move(heading)
            } else {
                lastMove = 0
            }
        case .aligned, .holding, .captured, .edgeReached, .refocus, .slowDown, .finished,
            .stageLimit, .paused:
            lastMove = 0
        }
    }
}
