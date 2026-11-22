import CoreGraphics
import Foundation

enum StageCalibrationFailure: Error, Equatable, LocalizedError {
    case barelyMoves(StageAxis)
    case lostTracking
    case parallel
    case noAxes

    var errorDescription: String? {
        switch self {
        case .barelyMoves(let axis): "Servo \(axis.letter) barely moves the picture"
        case .lostTracking: "Lost tracking, move to a patch with more particles"
        case .parallel:
            "Servo axes look parallel: tracking probably slipped. Pick a smaller chunk, then Retry"
        case .noAxes: "Could not build the stage axes"
        }
    }
}

/// How the two servos move the picture, in fields per degree (the guide's screen-field axes).
struct StageServoMapping: Equatable {
    /// Fields per degree for the servo the firmware calls X, and for Y.
    var x: CGPoint
    var y: CGPoint
    /// The X servo moves the picture mostly up-down.
    var swapped: Bool
    var axes: StageAxes
    /// Degrees each servo turned before the picture began to move (linkage slack).
    var xSlackDegrees = 0.0
    var ySlackDegrees = 0.0

    /// Servo degrees (X, Y) that move the picture by `move` fields; nil if the servos are parallel.
    func degrees(forMove move: CGPoint) -> (x: Double, y: Double)? {
        let det = Double(x.x * y.y - y.x * x.y)
        guard abs(det) > 1e-9 else { return nil }
        let tx = Double(move.x)
        let ty = Double(move.y)
        return (
            (tx * Double(y.y) - Double(y.x) * ty) / det,
            (Double(x.x) * ty - tx * Double(x.y)) / det
        )
    }

    var summary: String {
        let dir = swapped ? "up-down (swapped)" : "left-right"
        return String(
            format:
                "X %.3f f/°, slack %.0f°; Y %.3f f/°, slack %.0f°. Servo X moves the picture %@. Tilt %.1f°, skew %.1f°",
            hypot(Double(x.x), Double(x.y)), xSlackDegrees, hypot(Double(y.x), Double(y.y)),
            ySlackDegrees, dir, axes.tiltDegrees, axes.skewDegrees)
    }
}

/// Measures how each servo moves the picture, from samples taken while one servo is jogged.
struct StageAutoCalibration {
    var minTravelFields = 0.3
    var maxDegrees = 90
    /// Samples this close to the first tracked one count as "has not started moving" (slack).
    var onsetFields = 0.03

    private struct Sample {
        var angle: Double
        var position: CGPoint
        var tracked: Bool
        /// Samples with the same run number were tracked without a break in between.
        var run: Int
    }
    private var samples: [StageAxis: [Sample]] = [:]
    private var runs: [StageAxis: Int] = [:]

    /// - Parameter afterGap: tracking broke since the last sample (the tracker re-anchors and
    ///   misses the motion in the gap), so this sample starts a new run.
    mutating func add(
        servo: StageAxis, angle: Double, position: CGPoint, tracking: TrackingState,
        afterGap: Bool = false
    ) {
        let tracked = tracking == .tracking
        if afterGap || !tracked || samples[servo]?.last?.tracked == false {
            runs[servo, default: 0] += 1
        }
        samples[servo, default: []].append(
            Sample(angle: angle, position: position, tracked: tracked, run: runs[servo, default: 0]))
    }

    /// The tracked samples split where tracking broke; the first run starts at the onset.
    private func trackedRuns(_ servo: StageAxis) -> [[Sample]] {
        var result: [[Sample]] = []
        for sample in (samples[servo] ?? []) where sample.tracked {
            if let last = result.last?.last, last.run == sample.run {
                result[result.count - 1].append(sample)
            } else {
                result.append([sample])
            }
        }
        if let first = result.first { result[0] = Array(first[onsetIndex(first)...]) }
        return result
    }

    private static func distance(_ a: Sample, _ b: Sample) -> Double {
        hypot(Double(a.position.x - b.position.x), Double(a.position.y - b.position.y))
    }

    /// Fields the picture has moved: each run's furthest point from its start, added up (the
    /// motion inside a gap is not seen, so runs are not compared with each other).
    func travel(of servo: StageAxis) -> Double {
        trackedRuns(servo).reduce(0) { total, run in
            total + (run.map { Self.distance($0, run[0]) }.max() ?? 0)
        }
    }

    /// Distinct angles among the tracked samples from the onset on (across runs).
    func movingAngles(of servo: StageAxis) -> Int {
        Set(trackedRuns(servo).flatMap { $0.map(\.angle) }).count
    }

    /// The angles to sweep a servo through so the lab's stage step sees `fields` of motion: the
    /// slack plus `fields / fieldsPerDegree`, rounded up, centred on `centre` and kept inside
    /// 0...180. nil when it needs more than 180 degrees or the servo does not move the picture.
    static func stageStepSweep(
        fieldsPerDegree: Double, slackDegrees: Double, fields: Double = 2.4, centre: Int = 90
    ) -> (start: Int, end: Int)? {
        guard fieldsPerDegree > 0 else { return nil }
        let span = Int((slackDegrees + fields / fieldsPerDegree).rounded(.up))
        guard span <= 180 else { return nil }
        let start = min(max(centre - span / 2, 0), 180 - span)
        return (start, start + span)
    }

    /// Degrees covered by the tracked samples.
    func degreesUsed(of servo: StageAxis) -> Double {
        let angles = (samples[servo] ?? []).map(\.angle)
        return (angles.max() ?? 0) - (angles.min() ?? 0)
    }

    /// Index (in one run) where the picture starts moving: the last sample still within
    /// `onsetFields` of the first one, so the fit starts at the onset.
    private func onsetIndex(_ run: [Sample]) -> Int {
        guard let first = run.first else { return 0 }
        let moving = run.firstIndex { Self.distance($0, first) > onsetFields }
        return max((moving ?? 1) - 1, 0)
    }

    /// Degrees from the first tracked sample to where the picture starts moving (0 if at once).
    func slackDegrees(of servo: StageAxis) -> Double {
        var first: [Sample] = []
        for sample in (samples[servo] ?? []) where sample.tracked {
            if let last = first.last, last.run != sample.run { break }
            first.append(sample)
        }
        guard first.count > 1 else { return 0 }
        return abs(first[onsetIndex(first)].angle - first[0].angle)
    }

    /// Fields per degree: least squares of position against angle within each run (each run
    /// keeps its own offset, since a gap shifts the position), from the onset on.
    func vector(for servo: StageAxis) -> Result<CGPoint, StageCalibrationFailure> {
        let all = samples[servo] ?? []
        let lost = all.filter { !$0.tracked }.count
        guard travel(of: servo) >= minTravelFields else {
            return .failure(lost > all.count - lost ? .lostTracking : .barelyMoves(servo))
        }
        var saa = 0.0
        var sax = 0.0
        var say = 0.0
        for run in trackedRuns(servo) where run.count > 1 {
            let n = Double(run.count)
            let ma = run.reduce(0) { $0 + $1.angle } / n
            let mx = run.reduce(0) { $0 + Double($1.position.x) } / n
            let my = run.reduce(0) { $0 + Double($1.position.y) } / n
            for s in run {
                saa += (s.angle - ma) * (s.angle - ma)
                sax += (s.angle - ma) * (Double(s.position.x) - mx)
                say += (s.angle - ma) * (Double(s.position.y) - my)
            }
        }
        guard saa > 1e-9 else { return .failure(.barelyMoves(servo)) }
        return .success(CGPoint(x: sax / saa, y: say / saa))
    }

    func mapping() -> Result<StageServoMapping, StageCalibrationFailure> {
        let vx: CGPoint
        let vy: CGPoint
        switch vector(for: .x) {
        case .success(let v): vx = v
        case .failure(let f): return .failure(f)
        }
        switch vector(for: .y) {
        case .success(let v): vy = v
        case .failure(let f): return .failure(f)
        }
        return Self.servoMapping(
            x: vx, y: vy, xSlack: slackDegrees(of: .x), ySlack: slackDegrees(of: .y))
    }

    /// The mapping for two servo vectors: checks they are not parallel and builds the axes
    /// (the servo that moves the picture more horizontally is the stage's X).
    static func servoMapping(
        x vx: CGPoint, y vy: CGPoint, xSlack: Double, ySlack: Double
    ) -> Result<StageServoMapping, StageCalibrationFailure> {
        let lengths = hypot(Double(vx.x), Double(vx.y)) * hypot(Double(vy.x), Double(vy.y))
        guard lengths > 0 else { return .failure(.parallel) }
        let cosine = abs(Double(vx.x * vy.x + vx.y * vy.y)) / lengths
        let angle = acos(min(cosine, 1)) * 180 / .pi
        let limits = StageAxesThresholds()
        // The angle between the two lines, folded to 0...90 (the sign of a servo is free).
        guard angle >= min(limits.minAxisAngleDegrees, 180 - limits.maxAxisAngleDegrees) else {
            return .failure(.parallel)
        }
        let swapped = abs(vx.y) > abs(vx.x)
        let horizontal = swapped ? vy : vx
        let vertical = swapped ? vx : vy
        guard
            let axes = StageAxes(
                xDirection: unit(horizontal, toward: CGPoint(x: 1, y: 0)),
                yDirection: unit(vertical, toward: CGPoint(x: 0, y: 1)))
        else { return .failure(.noAxes) }
        return .success(
            StageServoMapping(
                x: vx, y: vy, swapped: swapped, axes: axes, xSlackDegrees: xSlack,
                ySlackDegrees: ySlack))
    }

    private static func unit(_ v: CGPoint, toward t: CGPoint) -> CGPoint {
        let length = hypot(Double(v.x), Double(v.y))
        let sign: CGFloat = v.x * t.x + v.y * t.y < 0 ? -1 : 1
        return CGPoint(x: sign * v.x / length, y: sign * v.y / length)
    }
}
