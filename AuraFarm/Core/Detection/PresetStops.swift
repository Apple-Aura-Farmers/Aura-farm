import CoreGraphics
import Foundation

/// Counting at the stops of a preset path on the Terraloka stage. A stopped stage is known to be
/// still, so the model looks at each stop, whatever the tracker says; between stops it does not
/// look. These are the pure parts: which stop it is, how long it holds, where it is on the slide,
/// which detections belong to it. Numbers are `LiveCountThresholds` (PLACEHOLDER).

/// Servo angles, whole degrees.
struct StageAngles: Equatable {
    var x: Int
    var y: Int
}

/// Where a stop is, from the servo angles alone.
struct PresetStopGeometry: Equatable {
    var fieldsPerDegreeX: Double
    var fieldsPerDegreeY: Double
    var flipX: Bool
    var flipY: Bool

    /// How far the view travelled on screen (the guide's fields: x right, y down) for `dx` and `dy`
    /// degrees from the run's first stop. In the arrows' directions: Up is more Y degrees and Left
    /// fewer X degrees, unless flipped.
    func guideFields(dx: Int, dy: Int) -> CGPoint {
        CGPoint(
            x: Double(flipX ? -dx : dx) * fieldsPerDegreeX,
            y: -Double(flipY ? -dy : dy) * fieldsPerDegreeY)
    }
}

/// The part of the frame a stop counts in: a square of `fields` boxes centred on the field circle.
enum PresetStopCell {
    static func rect(centre: CGPoint, boxSide: Double, fields: Double) -> CGRect {
        let side = boxSide * fields
        return CGRect(x: centre.x - side / 2, y: centre.y - side / 2, width: side, height: side)
    }
}

/// A detection seen at a stop, for the lens dirt check at the next one.
struct StopSighting: Equatable {
    var label: String
    var centre: CGPoint
    var side: Double
}

enum StopDirt {
    /// Same label, centre within `share` of its side of one seen at the previous stop: dirt on the
    /// lens stays put on the frame although the stage moved.
    static func isDirt(
        label: String, centre: CGPoint, side: Double, previous: [StopSighting], share: Double
    ) -> Bool {
        previous.contains {
            $0.label == label
                && hypot(Double($0.centre.x - centre.x), Double($0.centre.y - centre.y)) <= share * side
        }
    }
}

/// Which stop the preset path is at, how many looks it has had and how long it has been held.
/// Times are capture times; time in a focus pause is not counted.
struct PresetStopTracker {
    struct Stop: Equatable {
        var id: Int
        var column: Int
        var angles: StageAngles
        /// Only frames captured after this belong to the stop.
        var beganAt: Double
        var looks = 0
        /// Seconds held, without a focus pause.
        var waited = 0.0
        /// Paused, or a hand has the stage: no looks, no time counted; the same stop goes on after.
        var suspended = false
    }

    /// The preset path runs: counting happens at stops only.
    var isEnabled = false
    private(set) var stop: Stop?
    /// Stops that had at least one look, not counting the current one.
    private(set) var stopsLooked = 0
    /// The angles of the run's first stop, which every position is measured from.
    private(set) var firstAngles: StageAngles?
    private var lastTick: Double?

    /// Stops with at least one look, including the current.
    var stopsWithLooks: Int { stopsLooked + ((stop?.looks ?? 0) > 0 ? 1 : 0) }
    /// A stop is on and not suspended.
    var isAtStop: Bool { stop.map { !$0.suspended } ?? false }

    /// A stop begins, or (same id) goes on after a pause. Returns the stop it replaced, finished.
    @discardableResult
    mutating func begin(id: Int, column: Int, angles: StageAngles, at time: Double) -> Stop? {
        if var current = stop, current.id == id {
            current.suspended = false
            stop = current
            lastTick = nil
            return nil
        }
        let finished = end()
        if firstAngles == nil { firstAngles = angles }
        stop = Stop(id: id, column: column, angles: angles, beganAt: time)
        lastTick = nil
        return finished
    }

    mutating func suspend() {
        guard var current = stop else { return }
        current.suspended = true
        stop = current
        lastTick = nil
    }

    /// The stop is over (the next move, a hand, a disconnect, the column or the run ending).
    @discardableResult
    mutating func end() -> Stop? {
        guard let finished = stop else { return nil }
        if finished.looks > 0 { stopsLooked += 1 }
        stop = nil
        lastTick = nil
        return finished
    }

    /// A new run: nothing is kept.
    mutating func reset() {
        stop = nil
        stopsLooked = 0
        firstAngles = nil
        lastTick = nil
    }

    /// Time passes (one analysed frame). A long gap counts as at most half a second.
    mutating func tick(at time: Double, inFocusPause: Bool) {
        defer { lastTick = time }
        guard var current = stop, !current.suspended, let last = lastTick, !inFocusPause else { return }
        current.waited += min(max(time - last, 0), 0.5)
        stop = current
    }

    /// A frame went to the detector for this stop.
    mutating func noteLook() {
        guard var current = stop, !current.suspended else { return }
        current.looks += 1
        stop = current
    }

    /// Why a frame may not go to the detector on account of the stops alone; nil at a stop with
    /// looks to spare.
    func skipReason(frameAt time: Double, thresholds: LiveCountThresholds = LiveCountThresholds())
        -> String?
    {
        guard let stop, !stop.suspended, time > stop.beganAt else { return "between_stops" }
        return stop.looks >= thresholds.stopMaxLooks ? "stop_done" : nil
    }

    /// The stop wants to be held longer: its dwell may be over, but it has fewer than the wanted
    /// looks and less than the longest time, and looks can happen at all (`canLook`).
    func holds(canLook: Bool, thresholds: LiveCountThresholds = LiveCountThresholds()) -> Bool {
        guard let stop, !stop.suspended, canLook else { return false }
        return stop.looks < thresholds.stopWantedLooks && stop.waited < thresholds.stopMaxSeconds
    }
}
