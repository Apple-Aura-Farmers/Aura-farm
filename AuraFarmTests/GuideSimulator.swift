import CoreGraphics
import Foundation

@testable import AuraFarm

/// A simulated drop: sample inside the circles, blank outside (and inside the holes).
struct SimulatedDrop {
    var circles: [(centre: CGPoint, radius: Double)]
    var holes: [(centre: CGPoint, radius: Double)] = []
    /// Square or rectangular sample, like a cover slip filled with sample.
    var rects: [CGRect] = []

    /// A sample that fills a rectangle.
    static func square(from origin: CGPoint, side: Double) -> SimulatedDrop {
        SimulatedDrop(circles: [], rects: [CGRect(x: origin.x, y: origin.y, width: side, height: side)])
    }

    func contains(_ point: CGPoint) -> Bool {
        let inside =
            circles.contains {
                hypot(Double(point.x - $0.centre.x), Double(point.y - $0.centre.y)) <= $0.radius
            } || rects.contains { $0.contains(point) }
        let hole = holes.contains {
            hypot(Double(point.x - $0.centre.x), Double(point.y - $0.centre.y)) <= $0.radius
        }
        return inside && !hole
    }

    /// Whether the point is in the sample but within `width` of its edge (probed in 8 directions).
    func isInEdgeBand(_ point: CGPoint, width: Double) -> Bool {
        guard contains(point) else { return false }
        return (0..<8).contains { index in
            let angle = Double(index) * .pi / 4
            return !contains(
                CGPoint(
                    x: point.x + CGFloat(cos(angle) * width), y: point.y + CGFloat(sin(angle) * width)))
        }
    }

    /// Points on a 0.2 field grid inside the drop.
    func gridPoints(step: Double = 0.2) -> [CGPoint] {
        let xs =
            circles.flatMap { [Double($0.centre.x) - $0.radius, Double($0.centre.x) + $0.radius] }
            + rects.flatMap { [Double($0.minX), Double($0.maxX)] }
        let ys =
            circles.flatMap { [Double($0.centre.y) - $0.radius, Double($0.centre.y) + $0.radius] }
            + rects.flatMap { [Double($0.minY), Double($0.maxY)] }
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
    /// Readings (by index) at which the tracker reports `.lost` for 5 readings.
    var lostAtReading: Int?
    var lostRaisesGap = false
    /// Soil slide: the glass outside the sample is as bright as the sample, so it reads blurry
    /// (not blank) with tracking paused, and an edge band flickers (see `edgeBandFields`).
    var soil = false
    /// The width of the flickering band just inside the edge, in fields (soil only).
    var edgeBandFields = 0.3
    /// In the band: low detail for this long, then detail for `bandDetailSeconds`, repeating.
    var bandLowSeconds = 0.6
    var bandDetailSeconds = 0.4
    /// Soil only: a flicker of low detail of 0.3 s starts at random about this often inside
    /// the sample (readings between flickers on average); nil for none. Seeded, so repeatable.
    var interiorFlickerEveryReadings: Int?
    private var randomState: UInt64 = 7
    private var interiorLowLeft = 0
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

    func run(maxReadings: Int = 40000) -> Result {
        var instructions: [GuideInstruction] = []
        var states: [String] = []
        var truths: [CGPoint] = []
        var count = 0
        wrongWayLeft = wrongWayFields
        while count < maxReadings, !guide.isFinished {
            count += 1
            seconds += 0.1
            let reading = makeReading(index: count)
            let output = guide.update(reading)
            instructions.append(output.instruction)
            if states.last != output.stateName { states.append(output.stateName) }
            if output.capture != nil {
                truths.append(truePosition)
                capturesSoFar += 1
            }
            if output.isFinished { break }
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
            rechecks: guide.rechecks, failedProbes: guide.failedProbes)
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
                    bias = CGPoint(
                        x: frozen.x + error.x - truePosition.x, y: frozen.y + error.y - truePosition.y)
                } else if pauseTruth == nil {
                    // Nothing was ever tracked: the position carries on from where it froze.
                    unconfirmed += 1
                    bias = CGPoint(x: frozen.x - truePosition.x, y: frozen.y - truePosition.y)
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
        return GuideReading(
            seconds: seconds, position: frozen, tracking: tracking, unconfirmedGaps: unconfirmed,
            viewClass: viewClass, speedFraction: lastMove / 1.0, isStill: lastMove == 0)
    }

    /// Whether the view shows enough detail to follow. Over blank glass never; on a soil slide
    /// also not during the low part of an edge-band flicker or an interior flicker.
    private func isDetailed() -> Bool {
        guard drop.contains(truePosition) else { return false }
        guard soil else { return true }
        if drop.isInEdgeBand(truePosition, width: edgeBandFields) {
            let cycle = bandLowSeconds + bandDetailSeconds
            if seconds.truncatingRemainder(dividingBy: cycle) < bandLowSeconds - 1e-9 { return false }
        }
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
        switch output.instruction {
        case .findSample:
            move(CGPoint(x: searchTarget.x - truePosition.x, y: searchTarget.y - truePosition.y))
        case .travel(let direction), .farAway(let direction):
            move(direction)
        case .move(let toward):
            let remaining = hypot(Double(toward.x), Double(toward.y))
            if overshootFields > 0, !overshotAlready, capturesSoFar >= 12, remaining <= 0.25 {
                overshotAlready = true
                overshootLeft = remaining + overshootFields
                pending = toward
            }
            move(toward)
        case .edgeGoBack(let toward), .stillNoDetail(let toward):
            move(toward)
        case .tooFar, .otherWay:
            if let target = output.target {
                move(CGPoint(x: target.x - frozen.x, y: target.y - frozen.y))
            } else {
                lastMove = 0
            }
        case .aligned, .holding, .captured, .refocus, .slowDown, .finished:
            lastMove = 0
        }
    }
}
