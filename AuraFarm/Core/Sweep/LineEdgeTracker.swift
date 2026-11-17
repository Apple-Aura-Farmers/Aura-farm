import Foundation

/// The numbers the full-cover-slip edge rule decides with. Data, not logic. All PLACEHOLDER and
/// UNCALIBRATED: `EdgeLineDetector` has only been logged so far, and in earlier runs it locked
/// onto the eyepiece's lighting falloff (Phase 2j) and read a diagonal corner band at the angle
/// limit (Phase 2k). Calibrate from the `edge_line_*` columns and the snapshots.
struct LineEdgeThresholds {
    /// A line more than this far from perpendicular to the heading (a side edge running along
    /// the column, for one) is not the edge for this leg. The 16 Nov corner band ran at about 45
    /// to 50 degrees.
    var maxAngleDegrees = 60.0
    /// A line that passes the rule but sits this far (or less) behind the cross is "behind": the
    /// helper went past it and is told to come back. PLACEHOLDER. Source: 16 Nov 2026 22:56, the
    /// top-edge line sat at offset -0.23 to -0.38 after the helper overshot.
    var maxBehindFields = 0.8
    /// While a valid line was seen this recently, "refocus" and "nothing to follow" are not shown
    /// in line mode; the line's own instruction is. PLACEHOLDER: the 22:56 gaps were about 2 s.
    var lineMemorySeconds = 2.0
    /// |slide residual| at most this counts as the line moving with the slide.
    var attachedResidualFields = 0.15
    /// At least this many of the last `attachedWindow` moving readings with a candidate line must
    /// be attached, so the line is proven to be ON THE SLIDE and not on the optics (the lighting
    /// falloff and the shadow patch stay fixed on screen).
    var attachedReadings = 3
    var attachedWindow = 5
    /// Confirmed only when the line is within this of the centre cross.
    var atCrossFields = 0.25
    /// A gap in the candidate shorter than this does not reset the state.
    var lostLineSeconds = 0.5
    /// The line is accepted as the edge only if the texture energy beyond it is at most this
    /// share of the energy before it (the space past a cover slip's edge is empty or sparse).
    /// This is the second factor of the line rule: with the strength it must hold, neither alone
    /// is enough. PLACEHOLDER. Source: the 22:04 dark left edge read 1.5 to 1.9 beyond against 40
    /// to 47 before (about 0.04), the 15:32 bright-field one about 0.01.
    var beyondShareMax = 0.25
    /// The second way in: the line is also accepted when beyond is at most this share of before AND
    /// the whole half of the box ahead is nearly empty (`maxAreaAheadShare`) AND the line is within
    /// `relaxedMaxAngleDegrees` of perpendicular. Bottom edges collect texture (mountant, debris)
    /// just past the line while the wider area ahead is empty. PLACEHOLDER. Source: 17 Nov 2026
    /// 21:38 and 22:12 runs: beyond/before at bottom ends 0.33 to 0.88 (top ends 0.01 to 0.14),
    /// area ahead/behind 0.02 to 0.10 at bottom ends.
    var relaxedBeyondShareMax = 0.6
    /// PLACEHOLDER. Source: the replay of both 17 Nov runs (`EdgeReplayTests`): 0.2 and 0.3 confirm
    /// the same bottom ends with no extra false ones; 0.5 adds false ones in both runs.
    var maxAreaAheadShare = 0.3
    var relaxedMaxAngleDegrees = 20.0
    /// A later candidate within this many degrees of a known (or rejected) edge's direction and
    /// within `knownEdgeFields` of its position is the same edge and is ignored. PLACEHOLDER.
    var knownEdgeAngleDegrees = 15.0
    var knownEdgeFields = 0.5
    /// "Not an edge. Keep going" stays this long after the helper says so.
    var notAnEdgeSeconds = 2.0
}

/// An edge the route has met, in guide coordinates, so the same line is not found twice: the
/// 16 Nov 2026 15:32 run confirmed the left edge, and on the way to column 1 the same line, now
/// at the cross, confirmed again and ended column 1's up leg after a quarter of a field.
struct LineEdgeMemory: Equatable {
    struct Entry: Equatable {
        /// The heading the edge was found along (screen unit vector), and its angle from
        /// perpendicular to it.
        var normal: CGPoint
        var angleDegrees: Double
        /// The position along `normal`: the reading's position dotted with it plus the offset.
        var along: Double
    }

    private(set) var known: [Entry] = []
    private(set) var rejected: [Entry] = []

    static func entry(
        normal: CGPoint, position: CGPoint, offsetFields: Double, angleDegrees: Double
    ) -> Entry {
        Entry(
            normal: normal, angleDegrees: angleDegrees,
            along: Double(position.x * normal.x + position.y * normal.y) + offsetFields)
    }

    mutating func recordKnown(_ entry: Entry) { known.append(entry) }
    mutating func recordRejected(_ entry: Entry) { rejected.append(entry) }
    /// Rejected lines are kept for the rest of the current leg or run.
    mutating func clearRejected() { rejected = [] }

    /// Whether a candidate seen along `normal` from `position` is a known or rejected edge.
    ///
    /// A known edge is the one the view has just left behind: a candidate looking back at it (the
    /// opposite heading) is ignored. The same heading is not: the zig-zag meets the same top and
    /// bottom edge line again on every column, and each leg must end on it. A rejected line is
    /// ignored whichever way it is approached, for the rest of the leg or run.
    func ignores(
        normal: CGPoint, position: CGPoint, offsetFields: Double, angleDegrees: Double,
        thresholds: LineEdgeThresholds
    ) -> Bool {
        let matches = { (entry: Entry, needsOpposite: Bool) -> Bool in
            let dot = Double(normal.x * entry.normal.x + normal.y * entry.normal.y)
            if needsOpposite, dot > 0 { return false }
            let apart = acos(min(abs(dot), 1)) * 180 / .pi
            let lineApart =
                dot >= 0
                ? abs(angleDegrees - entry.angleDegrees) : abs(angleDegrees + entry.angleDegrees)
            let here =
                Double(position.x * entry.normal.x + position.y * entry.normal.y)
                + offsetFields * dot
            return apart <= thresholds.knownEdgeAngleDegrees
                && lineApart <= thresholds.knownEdgeAngleDegrees
                && abs(here - entry.along) <= thresholds.knownEdgeFields
        }
        return known.contains { matches($0, true) } || rejected.contains { matches($0, false) }
    }
}

/// Which rule accepted a line as an edge candidate: the strict beyond/before share, or the empty
/// area ahead. The word written in the CSV's `line_accept` column.
enum LineAccept: String, Equatable {
    case strict, area
}

/// How far a line has got toward being the edge.
enum LineEdgeState: String, Equatable {
    case none, ahead, attached, confirmed
    /// A valid line just behind the cross: the helper must come back to it.
    case behind

    /// The word written in the CSV's `line_state` column.
    var csvName: String { rawValue }
}

/// Decides, from the edge-line detector's results, when a line across the box is the edge of a
/// cover slip that the sample fills, for the full-cover-slip mode. Pure: the route feeds one
/// reading at a time.
///
/// none -> ahead (a candidate line, within the angle limit, ahead or at the cross) -> attached
/// (seen moving with the slide in enough moving readings) -> confirmed (attached, within
/// `atCrossFields`, still present, and the slide still for `confirmSeconds` in a row). Moving
/// resets the confirmation timer. A line never seen to move with the slide is never confirmed.
struct LineEdgeTracker {
    var thresholds: LineEdgeThresholds
    /// `EdgeConfirmationThresholds.confirmSeconds`.
    var confirmSeconds: Double

    /// Whether the rule confirms by itself after `confirmSeconds` at rest. When it does not (the lab
    /// asks the helper), it stops at `attached` at the cross and waits to be told.
    var confirmsAutomatically = true

    private(set) var state = LineEdgeState.none
    /// How many of the last moving readings with a candidate line were attached.
    private(set) var attachedCount = 0
    /// The latest usable line's offset along the heading, in fields, and its angle; nil without
    /// one.
    private(set) var offsetFields: Double?
    private(set) var angleDegrees: Double?
    /// The rule that accepted the latest usable line; nil without one.
    private(set) var accept: LineAccept?
    /// "line_attached" or "line_confirmed" on the reading that reached it, else empty.
    private(set) var event = ""

    private var recent: [Bool] = []
    private var lastSeen: Double?
    private var lastSeconds: Double?
    private var heldSeconds = 0.0

    init(thresholds: LineEdgeThresholds = LineEdgeThresholds(), confirmSeconds: Double = 1.0) {
        self.thresholds = thresholds
        self.confirmSeconds = confirmSeconds
    }

    /// Attached and within `atCrossFields`: the "Stay still, edge detected" stage.
    var atCross: Bool {
        guard state == .attached, let offsetFields else { return false }
        return abs(offsetFields) <= thresholds.atCrossFields
    }

    /// The line is at the cross and the slide has rested on it, but it was never seen to move
    /// with the slide: the helper must step back and come forward to prove it.
    func needsProof(_ reading: GuideReading) -> Bool {
        guard state == .ahead, let offsetFields else { return false }
        return abs(offsetFields) <= thresholds.atCrossFields
            && reading.isStill(for: confirmSeconds)
    }

    /// The space past a cover slip's edge is empty or sparse: little texture energy beyond the
    /// line against before it (strict), or somewhat more but with the whole half ahead nearly
    /// empty and the line near perpendicular (area). Unknown energies pass as strict; an unknown
    /// area ahead cannot pass as area. nil when neither holds.
    private func acceptRule(_ line: EdgeLine, areaAheadShare: Double?) -> LineAccept? {
        guard let before = line.beforeEnergy, let beyond = line.beyondEnergy else { return .strict }
        if beyond <= thresholds.beyondShareMax * before { return .strict }
        if beyond <= thresholds.relaxedBeyondShareMax * before,
            let area = areaAheadShare, area <= thresholds.maxAreaAheadShare,
            abs(line.angleDegrees) <= thresholds.relaxedMaxAngleDegrees
        {
            return .area
        }
        return nil
    }

    @discardableResult
    mutating func update(_ reading: GuideReading) -> LineEdgeState {
        event = ""
        let now = reading.seconds
        let step = lastSeconds.map { min(max(now - $0, 0), 0.5) } ?? 0
        lastSeconds = now

        if let line = reading.edgeLine, line.isCandidate,
            abs(line.angleDegrees) <= thresholds.maxAngleDegrees,
            line.offsetFields >= -thresholds.maxBehindFields,
            let rule = acceptRule(line, areaAheadShare: reading.areaAheadShare)
        {
            lastSeen = now
            accept = rule
            offsetFields = line.offsetFields
            angleDegrees = line.angleDegrees
            let isBehind = line.offsetFields < -thresholds.atCrossFields
            if state == .none || state == .ahead || state == .attached, isBehind {
                state = .behind
                event = "edge_behind"
            } else if state == .behind, !isBehind {
                state = .ahead
            } else if state == .none {
                state = .ahead
            }
            if !reading.isStill {
                let attached = line.slideResidualFields.map {
                    abs($0) <= thresholds.attachedResidualFields
                }
                recent.append(attached ?? false)
                if recent.count > thresholds.attachedWindow {
                    recent.removeFirst(recent.count - thresholds.attachedWindow)
                }
                attachedCount = recent.filter { $0 }.count
            }
        }
        if let lastSeen, now - lastSeen > thresholds.lostLineSeconds {
            reset()
            lastSeconds = now
            return state
        }
        guard state != .none else { return state }

        if state == .ahead, attachedCount >= thresholds.attachedReadings {
            state = .attached
            event = "line_attached"
        }
        if state == .attached, let offsetFields, abs(offsetFields) <= thresholds.atCrossFields {
            heldSeconds = reading.isStill ? heldSeconds + step : 0
            if confirmsAutomatically, heldSeconds >= confirmSeconds - 1e-9,
                reading.isStill(for: confirmSeconds)
            {
                state = .confirmed
                event = "line_confirmed"
            }
        } else if state != .confirmed {
            heldSeconds = 0
        }
        return state
    }

    mutating func reset() {
        consume()
        event = ""
    }

    /// Takes the confirmed edge: the state starts afresh, but this reading still reports what
    /// reached it (`event`), until the next `update`.
    mutating func consume() {
        state = .none
        attachedCount = 0
        offsetFields = nil
        angleDegrees = nil
        accept = nil
        recent = []
        lastSeen = nil
        heldSeconds = 0
    }
}
