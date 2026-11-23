import CoreGraphics
import Foundation

/// The numbers `GuidedSweep` decides with. Data, not logic. All PLACEHOLDER: not calibrated.
struct GuidedSweepThresholds {
    /// Between spots along a column, in fields. 0.8 is a 20% overlap.
    var spotSpacingFields: Double = 0.8
    /// Between columns, in fields.
    var columnSpacingFields: Double = 0.8
    /// How long the view must show low detail, without a break, before it counts as the edge.
    /// PLACEHOLDER, from E1 (soil, cover slip edge): the edge zone flickered in and out of low
    /// detail for 0.6 s and 1.6 s before the solid stretch, and the interior flickered once for
    /// 0.3 s. 0.8 s ignores the interior flicker and the first edge flicker.
    var edgeSeconds: Double = 0.8
    /// How long detail must hold before a low-detail stretch counts as over, so a single
    /// reading of detail between two short low stretches (crossing a hole, a flickering edge)
    /// does not restart the timer. About the tracker's 3 readings to see detail again.
    /// PLACEHOLDER: not calibrated; E1's edge flicker had 0.4 s of detail between stretches.
    var edgeRecoverySeconds: Double = 0.2
    /// After the edge was found, how long low detail may last on the way back before the
    /// guide says "still no detail" (and refocus becomes a fair suggestion). PLACEHOLDER: a
    /// 1 mm trip back over blank glass at the slow speed (about 0.5 mm/s) takes about 2 s.
    var refocusAfterSeconds: Double = 6.0
    /// A half of the box with less sharpness than this has no detail. PLACEHOLDER: the same cut
    /// as the whole box (`DetailThresholds.minBoxSharpness`); calibrate from the `box_sharp_*`
    /// CSV columns.
    var halfLowDetailBelowSharpness: Double = 120
    /// A half-box edge needs the half ahead to be at most this share of the half behind: a real
    /// edge is a clear difference between the halves, not two halves near the cut.
    /// PLACEHOLDER: not calibrated; E1 soil edges read 50 against 250 or more (0.2).
    var halfContrastRatioMax: Double = 0.5
    /// In column legs, the two halves across the heading must not differ clearly: the lower
    /// is at least this share of the higher. A clear difference is the cover slip's side
    /// drifting into view (a stage that is skewed), not the end of the leg arriving.
    /// PLACEHOLDER: not calibrated.
    var sideBalanceMin: Double = 0.5
    /// A side imbalance is accepted as a CORNER of the cover slip when the low side faces a known
    /// edge x within this many fields of the column. PLACEHOLDER: the column inset 0.6 plus the
    /// box's half width 0.5. Source: failed_edge_detection.csv (16 Nov 2026, soil): at the top-left
    /// corner the halves across the heading read 600 against 90, with column 1 at the inset.
    var sideEdgeReachFields: Double = 1.1
    /// A corner also needs the box's sharpness to have dropped to at most this share of its median
    /// before the candidate (the 15 Nov corner went from about 1050 to 350), over the detail
    /// readings of the last `cornerLookbackSeconds`. PLACEHOLDER: the 16 Nov run accepted a sparse
    /// patch as a corner because uneven sides plus a known edge nearby were enough.
    var cornerBoxDropShare: Double = 0.5
    var cornerLookbackSeconds: Double = 3.0
    /// How far column 1 sits inside the left edge, toward the sample, when the edge was found
    /// at the centre cross. The box is 1 field wide, so 0.5 puts its edge on the cover slip's
    /// edge; 0.6 leaves a little margin for a skewed stage. PLACEHOLDER: not calibrated.
    var columnInsetFields: Double = 0.6
    /// The eyepiece circle's radius in fields (the guide's unit is the registration box side, the
    /// circle is larger), once the confirmed circle is known; nil until then.
    var eyepieceRadiusFields: Double?
    /// Clear space left between the glass edge of the view and the cover slip's left and right
    /// edges, beyond the circle's own radius, in fields. PLACEHOLDER: 0.15 field, a small margin
    /// for a skewed stage; not calibrated.
    var sideMarginFields: Double = 0.15
    /// How far the first column sits inside the left edge and the last inside the right edge:
    /// the circle's radius plus `sideMarginFields`, so that only sample is in view, never less than
    /// `columnInsetFields`. Without a known circle, `columnInsetFields`. The next column's start
    /// after a top or bottom edge uses it too (`stepY`).
    var sideInsetFields: Double {
        guard let radius = eyepieceRadiusFields else { return columnInsetFields }
        return max(radius + sideMarginFields, columnInsetFields)
    }
    /// After a long stretch with no detail, detail that returns matched within this of where
    /// the stretch began was blur, not an edge. PLACEHOLDER: not calibrated.
    var sameSpotFields: Double = 0.3
    /// What a candidate edge must pass before it counts: arrival, the half behind still sharp
    /// against the last sharp frame, and holding still. See `EdgeConfirmation`.
    var confirmation = EdgeConfirmationThresholds()
    /// A spot within this of an existing capture is passed without stopping.
    var duplicateSpotFields: Double = 0.4
    /// Spots to move inward along the previous column after a failed step right.
    var probeStrideSpots: Int = 1
    /// How far the middle of the first column may be from the row the left edge was found on
    /// before the left edge is looked for again, in fields.
    var recheckLeftFields: Double = 1.0
    var maxLeftRechecks: Int = 2
    /// Full-cover-slip mode: the sample fills the cover slip, so the edge is the cover slip's
    /// line (`LineEdgeTracker`) and not a patch of low detail. Half edges, blank boxes and
    /// uneven sides are still logged but decide nothing; there is no left-edge recheck and no
    /// inward probing, and a right edge on a step finishes the route. Off (legacy) is the
    /// detail-density rule.
    var fullCoverSlip = false
    var lineEdge = LineEdgeThresholds()
    /// Full-cover-slip mode: predicted top and bottom edges (`EdgePrediction`).
    var edgePrediction = EdgePredictionThresholds()
    /// Full-cover-slip mode: the cover slip is square (the usual 22 x 22 mm), so once the top and
    /// bottom edges are predicted the right edge is the left edge plus the slip's height. Off:
    /// unknown shape, no right-edge prediction. The core default is off; the lab setting "Cover
    /// slip" turns it on.
    var squareCoverSlip = false
    /// A step right that finds the right edge places one last column only when the view is more
    /// than this past the column just done; and a predicted last column closer than this to the
    /// column just done is not placed. PLACEHOLDER: the Phase 2u brief, one column spacing.
    var lastColumnMinFields: Double = 0.8
    /// Columns run parallel to the left edge's tilt when it was confirmed with a known angle of at
    /// most `maxSlipTiltDegrees` (the lab's "Columns follow the slip's tilt"). A top or bottom
    /// edge's tilt is used for the early provisional limit under the same cap. PLACEHOLDER;
    /// source: confirmed edges in earlier runs read 4.5 to 9 degrees even with the stage
    /// straightened, so 12 allows them and refuses a line that is not the slip's edge.
    var followsSlipTilt = true
    var maxSlipTiltDegrees: Double = 12
    /// A column leg's area ahead (`areaAheadShare`) at most this, with no accepted line, for
    /// `legEmptyAheadSeconds`: no further spot is placed, the leg seeks the edge. PLACEHOLDER;
    /// source: bottom edges in the 17 Nov runs read 0.02 to 0.10, sample interiors much higher.
    var emptyAheadShare: Double = 0.15
    var legEmptyAheadSeconds: Double = 0.5
    /// A spot capped by a line, a loop location or a flat prediction must be at least this far
    /// ahead of the view, else no further spot is placed. PLACEHOLDER: the brief's 0.2 field.
    var minCappedSpotAheadFields: Double = 0.2
    /// Clear space kept between a spot and a line the route can see: the eyepiece radius plus
    /// `sideMarginFields`, so the view stays inside the sample.
    var edgeSpotMarginFields: Double { sideInsetFields }
    /// The view nearly empty ahead (`areaAheadShare` at most `LineEdgeThresholds.maxAreaAheadShare`,
    /// view class thin or blank) for this long on a step right is the right edge. PLACEHOLDER: the
    /// Phase 2u brief.
    var emptyAheadSeconds: Double = 1.0
    /// Full-cover-slip mode: the rule never confirms an edge by itself; it reaches "Stay still,
    /// edge detected" and waits for the helper's answer (`SlideRoute.userEdge`). Off: it confirms
    /// after `confirmSeconds` at rest.
    var asksEdges = false
    /// At the end of a leg, a spot is also taken at the edge when it is further than this
    /// from every capture, so the last stretch is not left out.
    var edgeSpotMinFields: Double = 0.5
    /// Tries to reach a travel target before giving up and ending the route.
    var maxTravelRetries: Int = 5
    /// A spot within this of a recorded stage limit is at the limit (the leg ends after its
    /// capture, with no tap), and a spot beyond it is moved onto it. PLACEHOLDER: about half the
    /// alignment tolerance, so the limit is not asked for twice.
    var stageLimitToleranceFields: Double = 0.1
    /// The lab suggests the Stage limit button after this long on an instruction to move, travel
    /// or follow the arrow. PLACEHOLDER: a spot is about a field away and the slow speed is about
    /// half a millimetre a second, so a normal move takes 2 s; 6 s is a stage that will not go.
    var stageLimitHintSeconds: Double = 6.0
    /// Whether a blank arrived under a moving helper is judged from the readings WITH detail in
    /// this many seconds before it: on a blank or blurry frame the speed estimate is noise (Test 4's
    /// top edge read 0.28 to 1.05 with the position frozen). PLACEHOLDER: about 3 readings at the
    /// lab's rate.
    var checkEdgeLookbackSeconds: Double = 0.5
    var alignment = SpotAlignmentThresholds()
}

/// The route the guide walks. Works one reading at a time; see `GuidedSweep` for the
/// conventions.
///
/// 1. Find the sample. 2. Travel left until it ends (the left edge) and come back to the last
/// spot with sample: that x is column 1. 3. Sweep column 1 up from there to its top edge,
/// back, then down to its bottom edge, passing spots already captured. 4. If the middle of
/// column 1 is far from the row the left edge was found on, look for the left edge again from
/// the middle: a start near the top or bottom of a round drop finds an edge right of the
/// drop's leftmost point. 5. Step right from the column's end spot. A landing on sample is a
/// new column, swept toward the near edge first (the way the last column ended) and then the
/// other way. A landing on blank is a failed probe: go back, move inward along the previous
/// column and step again; when every spot of the previous column has been tried the sample is
/// finished.
///
/// Known limitation: a blank hole inside the sample looks like an edge, so the part of a
/// column beyond the hole is reached only if a later column's sweep covers it.
struct SlideRoute {
    enum SpotKind: Equatable { case leg, edgeSpot, step, inward, recheckTravel }
    enum Purpose: Equatable { case leftEdge, legEnd, stepRight, resume }
    enum Phase: Equatable {
        case findSample
        case runToLeftEdge
        case returning(Purpose)
        case spot(SpotKind)
        case finished
    }

    private struct Column {
        var number: Int
        var x: Double
        var minY: Double
        var maxY: Double
        /// -1 up, +1 down (screen y grows downward).
        var legDirection: Double
        var legsDone = 0
        var gapsAtStart: Int
        /// The direction the last leg went, once the column is done.
        var endDirection: Double = 0
        var endSpot = CGPoint.zero
        /// Where the last leg's edge was (a confirmed or marked line), along the leg axis; nil
        /// after a stage limit. The next column starts `columnInsetFields` inward from it.
        var edgeY: Double?
        /// Where the column began along the leg axis, and how its x changes with y (dx/dy): zero
        /// for a straight column, `-tan(left edge tilt)` for one that follows the slip's tilt.
        var startY = 0.0
        var slope = 0.0
        /// The last column: placed at the right edge less the inset, and the route finishes after it.
        var isLast = false
    }

    /// Where the helper said the stage runs out, in guide fields. Each is nil until one was
    /// recorded and is kept for every later column.
    struct StageLimits: Equatable {
        /// The smallest y (the top, an up leg) and the largest (the bottom, a down leg).
        var minY: Double?
        var maxY: Double?
        /// The smallest x (left) and the largest (right).
        var minX: Double?
        var maxX: Double?
    }

    /// What one reading made of the route.
    struct Output {
        var instruction: GuideInstruction
        var target: CGPoint?
        var capture: FramePlacement?
    }

    var thresholds: GuidedSweepThresholds
    private(set) var phase = Phase.findSample
    private(set) var placements: [FramePlacement] = []
    private(set) var finishReason: SweepFinishReason?
    private(set) var rechecks = 0
    private(set) var probeIndex = 0
    private(set) var failedProbes = 0
    private(set) var edgesReached = 0
    private(set) var edgesGoneBack = 0
    private(set) var limits = StageLimits()
    /// Set once the first spot of column 1 is ticked: live counting starts there.
    private(set) var countingStarted = false
    /// The helper asked to end after the current column.
    private(set) var pendingEnd = false

    /// Brief touch: where the view is against the current spot's window, how long it has been
    /// inside, and how many spots were passed without a touch.
    var spotWindow: SpotWindow? { alignment.window }
    var touchElapsed: Double { alignment.touchElapsed }
    var missedSpots: Int { alignment.missedCount }
    /// How far the view is from the current spot, in fields; infinity without one.
    var distanceToSpot: Double { alignment.distance }

    /// The width between the left edge (column 1 less its inset) and the right edge (a recorded
    /// stage limit, or where a step right found the line), in fields; nil unless both are known.
    var edgeSpanFields: Double? {
        guard let first = columns.first ?? current else { return nil }
        let left = first.x - thresholds.sideInsetFields
        let right =
            limits.maxX ?? rightEdgeX ?? (finishReason == .rightEdge ? Double(lastPosition.x) : nil)
        guard let right, right > left else { return nil }
        return right - left
    }

    /// The slip's height in fields, measured from the confirmed or marked top and bottom edges;
    /// nil until both sides have one. Read only: the route does not use it.
    var measuredHeightFields: Double? { prediction.meanHeight(atColumns: columns.map(\.x)) }

    private var alignment: SpotAlignment
    /// Tells a real edge from a blur. Called once per reading; see `confirm`.
    private var confirmation: EdgeConfirmation
    private var verdict = EdgeVerdict.none
    private var candidateNow = EdgeCandidate.none
    private var columns: [Column] = []
    private var current: Column?
    private var lastSample: CGPoint?
    /// When the current unbroken run of low-detail readings began.
    private var lowDetailSince: Double?
    /// When the run of detail readings that may end the stretch began.
    private var detailSince: Double?
    /// When the half ahead began to lack detail while the half behind still had it.
    private var halfEdgeSince: Double?
    private var heading = CGPoint(x: -1, y: 0)
    private var leftEdgeY = 0.0
    private var isRecheckRun = false
    private var stepBase: Int?
    private var pendingStepTarget: CGPoint?
    private var resumeTarget: (point: CGPoint, kind: SpotKind, holds: Bool)?
    private var travelRetries = 0
    /// When the helper got onto the current target (a spot to hold on), nil when not there.
    private var atTargetSince: Double?
    /// Where, and after how many blank returns, the current low-detail stretch began.
    private var stretchStart: (position: CGPoint, returns: Int)?
    /// Whether the current low-detail stretch began while the helper was moving normally (not
    /// still, not a speed spike): a blank that arrives that way is checked by stepping back.
    private var stretchWasMoving = false
    /// The latest readings with detail, `checkEdgeLookbackSeconds` back: what the helper was doing
    /// before the picture went.
    private var detailHistory: [(seconds: Double, isStill: Bool, speed: Double)] = []
    /// What the last reading answered, for a stage limit pressed where it does not apply.
    private var lastOutput = Output(instruction: .findSample, target: nil, capture: nil)
    /// Set once a stretch of blur has run past `refocusAfterSeconds` with nothing decided:
    /// what to compare the position and the returns against when detail comes back.
    private var longBlur: (position: CGPoint, returns: Int)?
    /// A rejection from the raw half-box conditions on this reading, for the CSV.
    private var rawReason = ""
    /// The box's sharpness on detail readings that were not an edge candidate, the last
    /// `cornerLookbackSeconds` before the newest: what a corner is judged against.
    private var cornerBoxHistory: [(seconds: Double, sharpness: Double)] = []
    private var cornerShare: Double?
    /// What the last reading made of the edge conditions, for the CSV.
    private var rawDiagnostics = EdgeDiagnostics()
    private var lineEdge: LineEdgeTracker
    /// Edges the line rule confirmed (or the helper did), and lines the helper rejected.
    private var edgeMemory = LineEdgeMemory()
    private var notAnEdgeUntil: Double?
    /// Where the view was after the last reading: `edgeHeading` is decided from it.
    private var lastPosition = CGPoint.zero
    /// Whether the view has been on the current column's x since it began: until then it is on
    /// the trip in from the edge, and no line is looked for. After that, drifting off the column
    /// does not stop the looking (22:04 run: no readings for 19 s with the helper off the x).
    private var reachedColumn = false
    /// When a valid line was last seen (any line state but none) and whether it was behind the
    /// cross: for `lineMemoryInstruction`.
    private var lineSeenAt: Double?
    private var lineSeenBehind = false
    /// A place on the leg where the helper was told "edge just behind", counted by EPISODES
    /// (`trackEpisodes`), whether or not the line was accepted in between.
    private struct EdgeSpot {
        /// Slide position along the heading (reading position dotted with it, plus the offset).
        var along: Double
        var angle: Double
        var count = 1
    }
    private var spots: [EdgeSpot] = []
    /// The spot the latest episode counted at: for the CSV.
    private var lastSpot: Int?
    /// The spot the helper is being asked about (frozen), nil when no repeat question is up.
    private var repeatAsk: EdgeSpot?
    /// Spots answered No on this leg: never asked about again.
    private var rejectedAlongs: [Double] = []
    /// Where an accepted line last was on this leg (slide position, angle).
    private var lastLine: (along: Double, angle: Double)?
    /// "Edge just behind" was being issued on the previous reading.
    private var inEpisode = false
    /// The repeat question was raised on this reading, for the CSV.
    private var repeatEvent = false
    /// Every confirmed or marked top and bottom edge point, and the lines through them.
    private var prediction = EdgePrediction()
    /// The leg has no more spots before the predicted edge: the helper travels on to the edge.
    private var approachingEdge = false
    /// The left edge's angle in the guide's axes (see `guideAngle`) when it was confirmed with a
    /// known angle within `maxSlipTiltDegrees`; the columns follow it. nil: straight columns.
    private(set) var slipTiltDegrees: Double?
    /// The angle (guide axes) the latest top and bottom edge was confirmed with; nil when unknown.
    private var topEdgeAngle: Double?
    private var bottomEdgeAngle: Double?
    /// Why the current leg target is limited, for the CSV (`SpotLimit.reason`, or "empty_ahead");
    /// empty when it is not.
    private var spotLimitReason = ""
    /// Since when a column leg's area ahead has been nearly empty with no line in sight.
    private var legEmptySince: Double?
    /// "Edge should be here. Confirm?" is showing, and the helper said no for this leg.
    private var expectedEdgeAsking = false
    private var expectedAskDismissed = false
    /// The step right found the right edge and was turned into the last column.
    private var rightEdgeSeen = false
    private var lastColumnNext = false
    private var emptyAheadSince: Double?
    private var lastAreaAheadShare: Double?
    /// The right edge's x and how it was found ("line", "empty" or "predicted"), once known.
    private(set) var rightEdgeX: Double?
    private(set) var rightEdgeSource = ""

    init(thresholds: GuidedSweepThresholds = GuidedSweepThresholds()) {
        self.thresholds = thresholds
        alignment = SpotAlignment(thresholds: thresholds.alignment)
        confirmation = EdgeConfirmation(
            thresholds: thresholds.confirmation, halfCut: thresholds.halfLowDetailBelowSharpness)
        lineEdge = LineEdgeTracker(
            thresholds: thresholds.lineEdge, confirmSeconds: thresholds.confirmation.confirmSeconds)
    }

    /// What the last reading made of the edge conditions, for the CSV. In full-cover-slip mode
    /// it also says how far the line has got, and the reading that attached or confirmed it
    /// carries that as its reason (which asks for a snapshot).
    var diagnostics: EdgeDiagnostics {
        var shown = rawDiagnostics
        shown.canMarkEdge = thresholds.fullCoverSlip && markHeading != nil
        if thresholds.fullCoverSlip {
            shown.edgeMode = "line"
            // The detail rules only log in line mode.
            shown.verdict = "off"
            shown.lineAtCross = lineEdge.atCross
            if lineEdge.event == "line_confirmed" { shown.feedback = "auto" }
            shown.lineState =
                lineEdge.event == "line_confirmed" ? "confirmed" : lineEdge.state.csvName
            shown.lineAttachedCount = lineEdge.attachedCount
            if !lineEdge.event.isEmpty { shown.reason = lineEdge.event }
            shown.lineAccept = lineEdge.accept?.rawValue ?? ""
            shown.areaAheadShare = lastAreaAheadShare
            let spot = repeatAsk ?? lastSpot.map { spots[$0] }
            shown.expectedEdgeAsk = expectedEdgeAsking || repeatAsk != nil
            shown.lineCrossings = spot?.count ?? 0
            shown.lineAlong = spot?.along
            shown.spotLimitReason = spotLimitReason
            shown.slipTiltDegrees = slipTiltDegrees
            if repeatEvent { shown.reason = "edge_question_repeat" }
            if let column = current, case .spot(.leg) = phase {
                shown.predictedEdgeAlong = predictedEdge(for: column)
            }
        }
        return shown
    }

    var isFinished: Bool { phase == .finished }
    /// The current column is the last one: placed at the right edge less the inset.
    var isLastColumn: Bool { current?.isLast ?? false }
    var columnNumber: Int { current?.number ?? 0 }

    mutating func finish(reason: SweepFinishReason) {
        phase = .finished
        finishReason = finishReason ?? reason
    }

    /// Whether a column is being swept: its legs, or the spot at the end of one.
    var columnInProgress: Bool {
        switch phase {
        case .spot(.leg), .spot(.edgeSpot), .returning(.legEnd): return current != nil
        default: return false
        }
    }

    /// Ends the run at once, from any phase. Does nothing once finished.
    mutating func endNow() {
        guard !isFinished else { return }
        pendingEnd = false
        finish(reason: .endedByHelper)
    }

    /// Ends when the current column finishes (at its far edge or a stage limit), instead of
    /// stepping right. With no column in progress it ends at once.
    mutating func endAfterColumn() {
        guard !isFinished else { return }
        if columnInProgress { pendingEnd = true } else { endNow() }
    }

    mutating func cancelEndAfterColumn() {
        guard !isFinished else { return }
        pendingEnd = false
    }

    var stateName: String {
        switch phase {
        case .findSample: return "find sample"
        case .runToLeftEdge: return isRecheckRun ? "recheck left edge" : "find left edge"
        case .returning: return "edge: go back"
        case .finished: return "finished"
        case .spot(let kind):
            let number = current?.number ?? 0
            let way = (current?.legDirection ?? 0) < 0 ? "up" : "down"
            switch kind {
            case .leg: return "column \(number) \(way)"
            case .edgeSpot: return "column \(number) edge spot"
            case .step: return "step right"
            case .inward: return "probe \(probeIndex)"
            case .recheckTravel: return "recheck: to middle"
            }
        }
    }

    // MARK: Reading

    mutating func update(_ reading: GuideReading) -> Output {
        repeatEvent = false
        lastOutput = advance(reading)
        trackEpisodes(reading)
        lastPosition = reading.position
        if case .spot(.leg) = phase, let column = current,
            abs(Double(reading.position.x) - columnX(column, at: Double(reading.position.y)))
                <= thresholds.alignment.alignToleranceFields
        {
            reachedColumn = true
        }
        return lastOutput
    }

    /// The direction "Mark edge here" marks along: the same as `edgeHeading` but wherever the view
    /// is, so an edge can be marked while the guide says to turn back toward the cross (the view
    /// off the column, past the spot, holding on a spot).
    var markHeading: CGPoint? {
        switch phase {
        case .runToLeftEdge: return CGPoint(x: -1, y: 0)
        case .spot(.leg): return current.map { CGPoint(x: 0, y: $0.legDirection) }
        case .spot(.step): return CGPoint(x: 1, y: 0)
        default: return nil
        }
    }

    /// The direction an edge line is looked for along (screen unit vector), or nil: screen left on
    /// the left-edge run, the leg's direction on a column leg (once the view has reached the
    /// column), screen right on a step right. It holds for the whole leg whatever the
    /// instruction (moving, holding, captured, too far, other way, nothing to follow, refocus).
    /// nil on returns, the trip in to a column's start, edge spots and travel.
    var edgeHeading: CGPoint? {
        switch phase {
        case .runToLeftEdge:
            return CGPoint(x: -1, y: 0)
        case .spot(.leg):
            guard let column = current, reachedColumn else { return nil }
            return CGPoint(x: 0, y: column.legDirection)
        case .spot(.step):
            return CGPoint(x: 1, y: 0)
        default:
            return nil
        }
    }

    private mutating func advance(_ reading: GuideReading) -> Output {
        if phase == .finished { return Output(instruction: .finished, target: nil, capture: nil) }

        let onSample = Self.isOnSample(reading)
        if onSample {
            lastSample = reading.position
            if var column = current, case .spot = phase {
                column.minY = min(column.minY, Double(reading.position.y))
                column.maxY = max(column.maxY, Double(reading.position.y))
                current = column
            }
        }
        if !Self.isLowDetail(reading) {
            detailHistory.append((reading.seconds, reading.isStill, reading.speedFraction))
            detailHistory.removeAll {
                reading.seconds - $0.seconds > thresholds.checkEdgeLookbackSeconds
            }
        }
        if Self.isLowDetail(reading) {
            if lowDetailSince == nil {
                stretchStart = (reading.position, reading.blankReturnCount)
                // Judged from before the picture went: the onset reading's own speed is noise.
                // Moving normally: the latest reading with detail is not still and none was
                // fast. No such reading (after a resume or a lost stretch) is not moving.
                let recent = detailHistory.filter {
                    reading.seconds - $0.seconds <= thresholds.checkEdgeLookbackSeconds
                }
                stretchWasMoving =
                    recent.last.map { !$0.isStill } == true
                    && (recent.map(\.speed).max() ?? 0)
                        < thresholds.confirmation.tooFastSpeedFraction
            }
            lowDetailSince = lowDetailSince ?? reading.seconds
            detailSince = nil
        } else if lowDetailSince != nil {
            detailSince = detailSince ?? reading.seconds
            if reading.seconds - (detailSince ?? reading.seconds) >= thresholds.edgeRecoverySeconds - 1e-9 {
                lowDetailSince = nil
                detailSince = nil
            }
        }

        rawReason = ""
        cornerShare = nil
        lastAreaAheadShare = reading.areaAheadShare
        rememberBoxSharpness(reading)
        updateLineEdge(reading)
        updateEmptyAhead(reading)
        let halfEdge = rawHalfEdge(reading)
        halfEdgeSince = halfEdge ? (halfEdgeSince ?? reading.seconds) : nil

        if case .spot = phase, alignment.holdsTarget, let target = alignment.target,
            hypot(
                Double(target.x - reading.position.x), Double(target.y - reading.position.y))
                <= thresholds.alignment.alignToleranceFields
        {
            atTargetSince = atTargetSince ?? reading.seconds
        } else {
            atTargetSince = nil
        }

        if let output = decideLongBlur(reading, onSample: onSample) { return output }
        confirm(reading)

        switch phase {
        case .finished:
            return Output(instruction: .finished, target: nil, capture: nil)
        case .findSample:
            let warning = alignment.warning(reading, allowsRefocus: false)
            if !Self.isLowDetail(reading), let warning { return plain(warning) }
            guard onSample else { return plain(.findSample) }
            phase = .runToLeftEdge
            heading = CGPoint(x: -1, y: 0)
            leftEdgeY = Double(reading.position.y)
            isRecheckRun = false
            return runToLeftEdge(reading)
        case .runToLeftEdge:
            return runToLeftEdge(reading)
        case .returning(let purpose):
            guard onSample else { return plain(returning(reading)) }
            return completeReturn(purpose, reading)
        case .spot(let kind):
            return spot(kind, reading)
        }
    }

    /// The half-box edge condition: the half ahead has no detail and is clearly worse than the
    /// half behind, which has; in column legs the halves across the heading do not clearly
    /// differ. Sets `rawReason` when the first part holds but the rest rejects it.
    private mutating func rawHalfEdge(_ reading: GuideReading) -> Bool {
        let cut = thresholds.halfLowDetailBelowSharpness
        guard let ahead = reading.aheadSharpness, let behind = reading.behindSharpness,
            reading.tracking == .tracking, ahead < cut, behind >= cut
        else { return false }
        guard ahead <= thresholds.halfContrastRatioMax * behind else {
            rawReason = "halves_too_close"
            return false
        }
        if phase == .spot(.leg), let a = reading.sideSharpnessA, let b = reading.sideSharpnessB,
            min(a, b) < thresholds.sideBalanceMin * max(a, b)
        {
            // A clear difference is the cover slip's side drifting into view, unless the low
            // side faces a known edge close by: then it is the corner and the end of the leg.
            guard lowSideFacesKnownEdge(reading, lowIsA: a < b) else {
                rawReason = "side_imbalance"
                return false
            }
            // Uneven sides next to a known edge are not enough: the corner also takes the sample
            // away from the edge behind, the edge ahead across the far side too, and the whole box
            // dropping.
            guard hasCornerEvidence(reading) else {
                rawReason = "corner_rejected"
                return false
            }
            rawReason = "corner"
        }
        return true
    }

    /// Keeps the box's sharpness of readings with detail that are not themselves the half-edge
    /// candidate, trimmed to the lookback from the newest, so the median stays what it was before
    /// the candidate began.
    private mutating func rememberBoxSharpness(_ reading: GuideReading) {
        let cut = thresholds.halfLowDetailBelowSharpness
        let candidate =
            reading.tracking == .tracking && (reading.aheadSharpness ?? cut) < cut
            && (reading.behindSharpness ?? 0) >= cut
        guard !Self.isLowDetail(reading), !candidate, let box = reading.boxSharpness else { return }
        cornerBoxHistory.append((reading.seconds, box))
        cornerBoxHistory.removeAll { reading.seconds - $0.seconds > thresholds.cornerLookbackSeconds }
    }

    /// aheadAway below the half cut, behindAway at or above it, and the box at most
    /// `cornerBoxDropShare` of its recent median. Missing numbers fail it.
    private mutating func hasCornerEvidence(_ reading: GuideReading) -> Bool {
        let cut = thresholds.halfLowDetailBelowSharpness
        guard let aheadAway = reading.quadAheadAway, let behindAway = reading.quadBehindAway,
            let box = reading.boxSharpness
        else { return false }
        let recent = cornerBoxHistory.map(\.sharpness).sorted()
        guard !recent.isEmpty else { return false }
        let share = box / max(recent[recent.count / 2], 1e-9)
        cornerShare = share
        return aheadAway < cut && behindAway >= cut && share <= thresholds.cornerBoxDropShare
    }

    /// The x positions the route knows an edge at: the left edge column 1 was set inside, and
    /// the recorded stage limits.
    var knownEdgeXs: [Double] {
        var edges = [limits.minX, limits.maxX].compactMap { $0 }
        if let first = columns.first ?? current { edges.append(first.x - thresholds.sideInsetFields) }
        return edges
    }

    /// Whether the side half with less detail lies toward a known edge within reach of the column.
    /// False without the side's screen direction.
    private func lowSideFacesKnownEdge(_ reading: GuideReading, lowIsA: Bool) -> Bool {
        guard let direction = reading.sideADirection else { return false }
        let towardLow = lowIsA ? Double(direction.x) : -Double(direction.x)
        let x = current?.x ?? Double(reading.position.x)
        // The reach was measured with the column 0.6 inside the edge; a wider side inset moves
        // the column away from the edge by the same amount, so the reach grows with it.
        let reach =
            thresholds.sideEdgeReachFields
            + (thresholds.sideInsetFields - thresholds.columnInsetFields)
        return knownEdgeXs.contains {
            abs(x - $0) <= reach && ($0 - x) * towardLow > 0
        }
    }

    /// After a stretch of blur that ran past `refocusAfterSeconds` without being decided, decides
    /// when detail comes back: the tracker took the picture back at the same place (it was
    /// blur: carry on exactly where it was), or it did not or the position moved (the edge was
    /// reached on the way back: complete the leg or the left edge return from here). nil when
    /// there is nothing to decide on this reading.
    private mutating func decideLongBlur(_ reading: GuideReading, onSample: Bool) -> Output? {
        guard let pending = longBlur, !Self.isLowDetail(reading), reading.tracking == .tracking
        else { return nil }
        switch phase {
        case .runToLeftEdge, .spot: break
        default:
            longBlur = nil
            return nil
        }
        let returned = reading.blankReturnCount > pending.returns
        let moved = hypot(
            Double(reading.position.x - pending.position.x),
            Double(reading.position.y - pending.position.y))
        let isBlur =
            !returned || (reading.lastBlankReturn == .matched && moved <= thresholds.sameSpotFields)
        // An edge is decided only at rest: while the helper is moving the decision waits (and in
        // full-cover-slip mode only the line decides an edge, so it is taken as blur).
        if !isBlur, !thresholds.fullCoverSlip,
            !reading.isStill(for: thresholds.confirmation.confirmSeconds)
        {
            rawReason = "moving"
            return nil
        }
        longBlur = nil
        if isBlur || thresholds.fullCoverSlip {
            // Blur: carry on where it was, nothing was decided.
            lowDetailSince = nil
            detailSince = nil
            confirmation.cancel()
            verdict = .none
            rawReason = "same_spot"
            return nil
        }
        rawDiagnostics = EdgeDiagnostics(candidate: "whole_box", verdict: "confirmed", reason: "moved")
        confirmation.cancel()
        verdict = .none
        return takeWholeBoxEdge(reading, completeNow: onSample)
    }

    private static func isOnSample(_ reading: GuideReading) -> Bool {
        reading.tracking == .tracking && (reading.viewClass == .sample || reading.viewClass == .thin)
    }

    /// Too little detail to follow, whatever the class: blank glass, blur, dark, or the tracker
    /// paused (NO DETAIL). On soil the sample background is as bright as the glass outside the
    /// cover slip, so outside reads as blurry, not blank; all of these mean the edge.
    private static func isLowDetail(_ reading: GuideReading) -> Bool {
        reading.tracking == .paused || [.blank, .blurry, .dark].contains(reading.viewClass)
    }

    /// Asks `EdgeConfirmation` what the raw conditions come to. The half-box condition (the
    /// half ahead without detail, the half behind with it) applies to the left edge runs and
    /// column legs; the whole-box one (low detail for `edgeSeconds`) to every travel. Steps
    /// right and probes keep only the whole-box one: a landing spot half over the sample is
    /// still a valid column.
    private mutating func confirm(_ reading: GuideReading) {
        var allowsHalf = false
        var allowsWhole = false
        switch phase {
        case .runToLeftEdge:
            allowsHalf = true
            allowsWhole = true
        case .spot(let kind):
            allowsHalf = kind == .leg
            allowsWhole = true
        default:
            break
        }
        var candidate = EdgeCandidate.none
        var since: Double?
        if allowsHalf, let halfEdgeSince {
            candidate = .halfEdge
            since = halfEdgeSince
        } else if allowsWhole, edgeReached(reading) {
            candidate = .wholeBoxLowDetail
            since = lowDetailSince
        }
        candidateNow = candidate
        verdict = confirmation.update(
            reading: reading, heading: heading, candidate: candidate, since: since,
            spotReachedAt: atTargetSince)
        let reason = rawReason.isEmpty ? confirmation.reason : rawReason
        rawDiagnostics = EdgeDiagnostics(
            candidate: candidate.csvName, verdict: verdict.csvName, reason: reason,
            cornerBoxShare: cornerShare)
        if thresholds.fullCoverSlip {
            // Logged above as it was computed (verdict written "off"), but it decides nothing and
            // says nothing: no check-edge, no checking, no blur, never an edge.
            verdict = .none
        }
    }

    /// Takes the confirmed verdict, once.
    private mutating func consumeConfirmation() {
        verdict = .none
        confirmation.cancel()
    }

    /// The direction the view is being sent, for the phases that have one.
    var guideHeading: CGPoint? {
        switch phase {
        case .runToLeftEdge: return heading
        case .spot(.leg), .spot(.edgeSpot), .spot(.step): return heading
        default: return nil
        }
    }

    /// Low detail has lasted `edgeSeconds`: this is the edge.
    private func edgeReached(_ reading: GuideReading) -> Bool {
        guard Self.isLowDetail(reading), let lowDetailSince else { return false }
        return reading.seconds - lowDetailSince >= thresholds.edgeSeconds - 1e-9
    }

    private func plain(_ instruction: GuideInstruction) -> Output {
        Output(instruction: instruction, target: nil, capture: nil)
    }

    // MARK: Predicted edges

    /// The predicted edge for the leg of `column`, along the leg axis; nil with fewer than two
    /// points on that side, or when the fit is not trusted (`predictionTrustFields`).
    private func predictedEdge(for column: Column) -> Double? {
        guard thresholds.fullCoverSlip else { return nil }
        return prediction.trustedAlong(column.legDirection < 0 ? .top : .bottom, at: column.x)
    }

    /// The right edge's x predicted from the left edge and the slip's height; nil unless the slip
    /// is square and both edges have a fit.
    private func predictedRightEdgeX() -> Double? {
        guard thresholds.fullCoverSlip, thresholds.squareCoverSlip, let first = columns.first,
            let height = prediction.meanHeight(atColumns: columns.map(\.x))
        else { return nil }
        return first.x - thresholds.sideInsetFields + height
    }

    /// What the route has predicted, for the trail mini-map.
    var predictedEdges: PredictedEdges {
        guard thresholds.fullCoverSlip, let first = columns.first ?? current else {
            return PredictedEdges()
        }
        let rightX = rightEdgeX ?? predictedRightEdgeX()
        let left = first.x - thresholds.sideInsetFields
        let furthest = max(columns.last?.x ?? first.x, current?.x ?? first.x)
        let right = rightX ?? (furthest + thresholds.columnSpacingFields)
        return PredictedEdges(
            top: prediction.fit(.top), bottom: prediction.fit(.bottom), rightX: rightX, leftX: left,
            points: prediction.top + prediction.bottom, xRange: left...max(right, left))
    }

    /// Where the column is across (x) at `y` along the leg: straight, or slanted to follow the
    /// slip's tilt. The slope is dx/dy, so the distance to a left edge with tilt `t` (which runs
    /// toward screen-left as it goes down for t > 0) stays constant: x(y) = x0 - tan(t) (y - y0).
    private func columnX(_ column: Column, at y: Double) -> Double {
        column.x + column.slope * (y - column.startY)
    }

    /// dx/dy of a column that follows the slip's tilt (0 when it does not).
    private var slipSlope: Double { -tan((slipTiltDegrees ?? 0) * .pi / 180) }

    /// The detector's angle (frame axes, from perpendicular to the heading) in the guide's axes: a
    /// frame whose axes map to the screen with a mirror (negative determinant) turns it round.
    private func guideAngle(_ degrees: Double, _ reading: GuideReading) -> Double {
        degrees * reading.frameHandedness
    }

    /// Remembers where a leg's edge was (the view's position plus the line's offset along the leg),
    /// and the angle it was confirmed with (nil: unknown, as a hand mark with no line).
    private mutating func noteLegEdge(
        _ reading: GuideReading, offsetFields: Double, angle: Double?
    ) {
        guard var column = current else { return }
        let y = Double(reading.position.y) + offsetFields * column.legDirection
        column.edgeY = y
        current = column
        if column.legDirection < 0 { topEdgeAngle = angle } else { bottomEdgeAngle = angle }
        prediction.record(column.legDirection < 0 ? .top : .bottom, x: column.x, along: y)
    }

    /// Aims at the next spot of the leg from `position`. A spot is never beyond the predicted
    /// edge less `spotEdgeMarginFields`: the spot at that limit is the last ordinary one, and
    /// after it the helper travels on to the edge (no more spots) until the line, the helper or
    /// the expected-edge answer ends the leg.
    private mutating func aimNextLegSpot(from position: CGPoint, column: Column) {
        let y = nextSpotY(from: Double(position.y), direction: column.legDirection, column: column)
        let side = column.legDirection
        if let limit = spotLimit(for: column, from: position), (y - limit.spotY) * side > 1e-6 {
            let limitPoint = CGPoint(x: columnX(column, at: limit.spotY), y: limit.spotY)
            let minAhead =
                limit.reason == "fitted_prediction" ? 0.05 : thresholds.minCappedSpotAheadFields - 1e-9
            if !isDuplicate(limitPoint), (limit.spotY - Double(position.y)) * side > minAhead {
                aim(at: limitPoint, from: position, kind: .leg, holds: true)
            } else {
                aim(
                    at: CGPoint(x: columnX(column, at: limit.edge), y: limit.edge), from: position,
                    kind: .leg, holds: false)
                approachingEdge = true
            }
            spotLimitReason = limit.reason
            return
        }
        aim(at: CGPoint(x: columnX(column, at: y), y: y), from: position, kind: .leg, holds: true)
    }

    /// The farthest a leg spot may be (`spotY`), the edge it keeps clear of, and why.
    private struct SpotLimit {
        var edge: Double
        var spotY: Double
        var reason: String
    }

    /// The tightest limit on the leg of `column` from what the route knows: an accepted line
    /// ahead and the edge-loop locations of this leg (both `edgeSpotMarginFields` short of the
    /// line), column 1's single edge point as a flat prediction (the same margin), or the fitted,
    /// trusted prediction (`spotEdgeMarginFields`). nil when nothing limits it.
    private func spotLimit(for column: Column, from position: CGPoint) -> SpotLimit? {
        guard thresholds.fullCoverSlip else { return nil }
        let side = column.legDirection
        var best: SpotLimit?
        func consider(_ edge: Double, _ margin: Double, _ reason: String) {
            let limit = SpotLimit(edge: edge, spotY: edge - side * margin, reason: reason)
            if let current = best, (limit.spotY - current.spotY) * side >= 0 { return }
            best = limit
        }
        let margin = thresholds.edgeSpotMarginFields
        if lineEdge.state == .ahead || lineEdge.state == .attached,
            let offset = lineEdge.offsetFields
        {
            consider(Double(position.y) + offset * side, margin, "line")
        }
        // A location's `along` is the slide position along the leg heading (0, side).
        for spot in spots { consider(spot.along * side, margin, "loop_location") }
        if let edge = predictedEdge(for: column) {
            consider(edge, thresholds.edgePrediction.spotEdgeMarginFields, "fitted_prediction")
        } else {
            let points = side < 0 ? prediction.top : prediction.bottom
            if points.count == 1, let point = points.first {
                // Through column 1's edge point, at the angle it was confirmed with (guide axes)
                // when that is known and within `maxSlipTiltDegrees`; flat otherwise. A top or
                // bottom edge has the screen slope dy/dx = tan(angle).
                let angle = side < 0 ? topEdgeAngle : bottomEdgeAngle
                if let angle, abs(angle) <= thresholds.maxSlipTiltDegrees {
                    let across = columnX(column, at: Double(point.y)) - Double(point.x)
                    consider(
                        Double(point.y) + tan(angle * .pi / 180) * across, margin,
                        "tilted_prediction")
                } else {
                    consider(Double(point.y), margin, "flat_prediction")
                }
            }
        }
        return best
    }

    /// Spot alignment must not contradict an edge line that is still ahead. With an accepted line
    /// 0 to `lineLeadFields` ahead, too far, the wrong way and a missed spot become "a little
    /// further" (or "stay still" at the cross), and past the leg's last ordinary spot (seeking the
    /// edge) they become the arrow along the leg. Still `nudgeStillSeconds` with the line beyond
    /// the at-cross band is the same instruction with a nudge.
    private func edgeLeadInstruction(
        _ instruction: GuideInstruction, _ reading: GuideReading, legDirection: Double
    ) -> GuideInstruction {
        let direction = CGPoint(x: 0, y: legDirection)
        let lineEdgeThresholds = thresholds.lineEdge
        let lead = lineEdge.leadFields
        let nudge =
            (lead ?? 0) > lineEdgeThresholds.atCrossFields
            && reading.isStill(for: lineEdgeThresholds.nudgeStillSeconds)
        switch instruction {
        case .tooFar, .otherWay, .missedSpot:
            if lead != nil {
                return lineEdge.atCross ? .edgeDetected : .lineLead(direction: direction, nudge: nudge)
            }
            return approachingEdge ? .travel(direction: direction) : instruction
        case .move, .farAway, .aligned:
            return nudge ? .lineLead(direction: direction, nudge: true) : instruction
        default:
            return instruction
        }
    }

    /// The expected-edge ask: the view is more than `overshootFields` past the predicted edge with
    /// nothing ahead and no edge found. Never accepted without the helper. nil when not asking.
    private mutating func expectedEdgeOutcome(
        _ kind: SpotKind, _ reading: GuideReading, target: CGPoint
    ) -> Output? {
        guard thresholds.fullCoverSlip, kind == .leg, let column = current,
            let edge = predictedEdge(for: column)
        else {
            expectedEdgeAsking = false
            return nil
        }
        let passed = (Double(reading.position.y) - edge) * column.legDirection
        let empty = (reading.areaAheadShare ?? 1) <= thresholds.lineEdge.maxAreaAheadShare
        guard passed > thresholds.edgePrediction.overshootFields, !expectedAskDismissed,
            expectedEdgeAsking || empty
        else {
            expectedEdgeAsking = false
            return nil
        }
        expectedEdgeAsking = true
        return Output(instruction: .expectedEdge, target: target, capture: nil)
    }

    // MARK: Stage limit

    /// The helper says the stage cannot go further. Records the limit and turns as at an edge:
    /// on a column leg the leg ends, on the left edge run column 1 starts here, on a step right
    /// the route is over. In any other phase it changes nothing and returns the last answer.
    mutating func stageLimitReached(_ reading: GuideReading) -> Output {
        let x = Double(reading.position.x)
        let y = Double(reading.position.y)
        switch phase {
        case .spot(let kind) where kind == .leg || kind == .edgeSpot:
            guard let column = current else { return lastOutput }
            if column.legDirection < 0 { limits.minY = y } else { limits.maxY = y }
            current?.edgeY = nil
            if kind == .edgeSpot {
                // Already ending the leg here: the spot is the limit, carry on to its capture.
                lastOutput.instruction = .stageLimit
                return lastOutput
            }
            edgesReached += 1
            halfEdgeSince = nil
            consumeConfirmation()
            lastOutput = endLeg(reading)
            lastOutput.instruction = .stageLimit
        case .runToLeftEdge:
            limits.minX = x
            consumeConfirmation()
            lastOutput = completeReturn(.leftEdge, reading)
            lastOutput.instruction = .stageLimit
        case .spot(.step):
            limits.maxX = x
            finish(reason: .stageLimit)
            lastOutput = plain(.finished)
        default:
            break
        }
        return lastOutput
    }

    // MARK: Pausing

    /// Forgets every running timer and the confirmation under way, so nothing fires because of
    /// a gap in the readings (a pause). The route's place, targets and captures stay.
    mutating func clearTimers() {
        lowDetailSince = nil
        detailSince = nil
        halfEdgeSince = nil
        atTargetSince = nil
        longBlur = nil
        stretchStart = nil
        stretchWasMoving = false
        detailHistory = []
        cornerBoxHistory = []
        lineEdge.reset()
        inEpisode = false
        emptyAheadSince = nil
        notAnEdgeUntil = nil
        verdict = .none
        candidateNow = .none
        rawReason = ""
        confirmation.cancel()
        alignment.clearHold()
    }

    // MARK: Left edge

    private mutating func runToLeftEdge(_ reading: GuideReading) -> Output {
        if let left = limits.minX,
            Double(reading.position.x) <= left + thresholds.stageLimitToleranceFields
        {
            // A look for the left edge again stops where the stage ran out before.
            var output = completeReturn(.leftEdge, reading)
            output.instruction = .stageLimit
            return output
        }
        if thresholds.fullCoverSlip { return runToLeftEdgeByLine(reading) }
        switch verdict {
        case .confirmed:
            let half = candidateNow == .halfEdge
            consumeConfirmation()
            if half {
                // The edge is at the centre: as if the way back had just been completed here.
                edgesReached += 1
                halfEdgeSince = nil
                var output = completeReturn(.leftEdge, reading, edgeAtCentre: true)
                output.instruction = .edgeReached
                return output
            }
            return takeWholeBoxEdge(reading, completeNow: false)
        case .checking(let progress):
            return plain(.checkingEdge(progress: progress))
        case .blur:
            // The same content out of focus, not an edge: carry on from where it was.
            return plain(blurInstruction(reading))
        case .none:
            break
        }
        if let warning = alignment.warning(reading, allowsRefocus: false) { return plain(warning) }
        return plain(.travel(direction: CGPoint(x: -1, y: 0)))
    }

    /// Full-cover-slip mode on the left-edge run: the line decides, at rest and attached.
    private mutating func runToLeftEdgeByLine(_ reading: GuideReading) -> Output {
        if lineEdge.state == .confirmed,
            let output = takeLineEdge(
                reading, offsetFields: lineEdge.offsetFields ?? 0,
                angleDegrees: lineEdge.angleDegrees ?? 0)
        {
            return output
        }
        if let instruction = lineInstruction(reading, backward: CGPoint(x: 1, y: 0)) {
            return plain(instruction)
        }
        if let warning = alignment.warning(reading, allowsRefocus: false) { return plain(warning) }
        if let remembered = lineMemoryInstruction(reading, backward: CGPoint(x: 1, y: 0)) {
            return plain(remembered)
        }
        if Self.isLowDetail(reading) { return plain(.nothingToFollow) }
        return plain(.travel(direction: CGPoint(x: -1, y: 0)))
    }

    /// What the line says to do, before anything else: keep going after "not an edge", stay still
    /// at the cross, or step back and come forward when the line at the cross was never seen to
    /// move with the slide. nil when it says nothing.
    private func lineInstruction(_ reading: GuideReading, backward: CGPoint) -> GuideInstruction? {
        if let until = notAnEdgeUntil, reading.seconds < until { return .notAnEdge }
        if lineEdge.needsProof(reading) { return .checkEdge(toward: backward) }
        if lineEdge.atCross { return .edgeDetected }
        if lineEdge.state == .behind { return .edgeBehind(toward: backward) }
        return nil
    }

    /// While a valid line was seen within `lineMemorySeconds`, its own words ("edge just behind"
    /// or "edge line ahead") stand in for "refocus" and "nothing to follow": the box is blank
    /// because the helper went past the line, not because the picture is wrong. nil otherwise.
    private func lineMemoryInstruction(
        _ reading: GuideReading, backward: CGPoint
    ) -> GuideInstruction? {
        guard thresholds.fullCoverSlip, let seen = lineSeenAt,
            reading.seconds - seen <= thresholds.lineEdge.lineMemorySeconds
        else { return nil }
        return lineSeenBehind ? .edgeBehind(toward: backward) : .lineAhead
    }

    /// Feeds the line tracker on the phases that look for an edge (the left-edge run, a column
    /// leg and a step right); any other phase forgets the line.
    private mutating func updateLineEdge(_ reading: GuideReading) {
        guard thresholds.fullCoverSlip else { return }
        guard let heading = edgeHeading else {
            lineEdge.reset()
            lineSeenAt = nil
            legEmptySince = nil
            resetEpisodes(keepingRejected: true)
            return
        }
        var seen = reading
        if let line = reading.edgeLine {
            // A line measured along another heading is not this leg's; a known or rejected
            // edge is not found a second time.
            let other = reading.edgeLineHeading.map {
                Double($0.x * heading.x + $0.y * heading.y) < 0.9
            }
            if other == true
                || edgeMemory.ignores(
                    normal: heading, position: reading.position, offsetFields: line.offsetFields,
                    angleDegrees: line.angleDegrees, thresholds: thresholds.lineEdge)
            {
                seen.edgeLine = nil
            }
        }
        lineEdge.confirmsAutomatically = !thresholds.asksEdges
        lineEdge.update(seen)
        if lineEdge.state != .none {
            lineSeenAt = reading.seconds
            lineSeenBehind = lineEdge.state == .behind
        }
        if case .spot(.leg) = phase, lineEdge.state == .none,
            (reading.areaAheadShare ?? 1) <= thresholds.emptyAheadShare
        {
            legEmptySince = legEmptySince ?? reading.seconds
        } else {
            legEmptySince = nil
        }
        if lineEdge.seenNow, let offset = lineEdge.offsetFields, let angle = lineEdge.angleDegrees {
            let along =
                Double(reading.position.x * heading.x + reading.position.y * heading.y) + offset
            lastLine = (along, angle)
        }
    }

    /// Counts EPISODES of "edge just behind" on a column leg: one starts when the route issues
    /// `edgeBehind` and ends when it stops. Each is placed at the line's last accepted slide
    /// position; within `sameLineFields` of a recorded spot it adds 1 to that spot's count, else
    /// it starts a new spot (the others keep theirs). Dropouts of the line reset nothing. At
    /// `repeatEpisodes` the helper is asked about that spot (`edgeQuestionSnapshot`), whatever
    /// `asksEdges` says. Reset by `resetEpisodes`: the leg ending, an edge, an answer.
    private mutating func trackEpisodes(_ reading: GuideReading) {
        var behind = false
        if case .spot(.leg) = phase, case .edgeBehind = lastOutput.instruction { behind = true }
        defer { inEpisode = behind }
        guard behind, !inEpisode, repeatAsk == nil, let line = lastLine else { return }
        let near = thresholds.lineEdge.sameLineFields
        if rejectedAlongs.contains(where: { abs($0 - line.along) <= near }) { return }
        if let index = spots.firstIndex(where: { abs($0.along - line.along) <= near }) {
            spots[index].count += 1
            spots[index].along = line.along
            spots[index].angle = line.angle
            lastSpot = index
        } else {
            spots.append(EdgeSpot(along: line.along, angle: line.angle))
            lastSpot = spots.count - 1
        }
        if let index = lastSpot, spots[index].count >= thresholds.lineEdge.repeatEpisodes {
            repeatAsk = spots[index]
            repeatEvent = true
        }
    }

    private mutating func resetEpisodes(keepingRejected: Bool = false) {
        spots = []
        lastSpot = nil
        repeatAsk = nil
        lastLine = nil
        inEpisode = false
        if !keepingRejected { rejectedAlongs = [] }
    }

    /// Where the accepted line is on the column's leg now (guide fields); nil without one.
    private func legLinePoint(_ reading: GuideReading, column: Column) -> CGPoint? {
        guard let offset = lineEdge.offsetFields else { return nil }
        let y = Double(reading.position.y) + offset * column.legDirection
        return CGPoint(x: columnX(column, at: y), y: y)
    }

    /// Times how long the view has been nearly empty ahead on a step right: the right edge (or
    /// empty glass) when it lasts `emptyAheadSeconds`.
    private mutating func updateEmptyAhead(_ reading: GuideReading) {
        guard thresholds.fullCoverSlip, phase == .spot(.step), !rightEdgeSeen,
            let area = reading.areaAheadShare, area <= thresholds.lineEdge.maxAreaAheadShare,
            reading.viewClass == .thin || reading.viewClass == .blank
        else {
            emptyAheadSince = nil
            return
        }
        emptyAheadSince = emptyAheadSince ?? reading.seconds
    }

    /// A step right found the right edge at `edgeX`. When the view is more than
    /// `lastColumnMinFields` past the column just done, one last column goes at the edge less the
    /// inset (the step's target is turned back to it); otherwise the route finishes here.
    private mutating func rightEdgeFound(
        _ reading: GuideReading, edgeX: Double, source: String
    ) -> Output {
        rightEdgeX = edgeX
        rightEdgeSource = source
        lineEdge.consume()
        lineSeenAt = nil
        emptyAheadSince = nil
        let x = edgeX - thresholds.sideInsetFields
        guard !rightEdgeSeen, let index = stepBase,
            Double(reading.position.x) - columns[index].x > thresholds.lastColumnMinFields,
            x > columns[index].x
        else {
            finish(reason: .rightEdge)
            return plain(.finished)
        }
        rightEdgeSeen = true
        lastColumnNext = true
        let target = CGPoint(x: x, y: stepY(columns[index]))
        aim(at: target, from: reading.position, kind: .step, holds: !isDuplicate(target))
        return Output(instruction: .aligned, target: target, capture: nil)
    }

    /// Takes the line at the cross as the edge (the rule's, or the helper's): remembers it so it is
    /// not found again, and ends the left-edge run, the leg or the route as a confirmed edge does.
    private mutating func takeLineEdge(
        _ reading: GuideReading, offsetFields: Double, angleDegrees: Double,
        along: CGPoint? = nil, angleKnown: Bool = true
    ) -> Output? {
        guard let heading = along ?? edgeHeading else { return nil }
        edgeMemory.recordKnown(
            LineEdgeMemory.entry(
                normal: heading, position: reading.position, offsetFields: offsetFields,
                angleDegrees: angleDegrees))
        edgeMemory.clearRejected()
        lineEdge.consume()
        lineSeenAt = nil
        resetEpisodes()
        halfEdgeSince = nil
        switch phase {
        case .runToLeftEdge:
            edgesReached += 1
            // The columns follow the left edge's tilt when it was seen with a known angle.
            let tilt = guideAngle(angleDegrees, reading)
            slipTiltDegrees =
                thresholds.followsSlipTilt && angleKnown && abs(tilt) <= thresholds.maxSlipTiltDegrees
                ? tilt : nil
            var output = completeReturn(.leftEdge, reading, edgeAtCentre: true)
            output.instruction = .edgeReached
            return output
        case .spot(.leg):
            edgesReached += 1
            noteLegEdge(
                reading, offsetFields: offsetFields,
                angle: angleKnown ? guideAngle(angleDegrees, reading) : nil)
            var output = endLeg(reading)
            output.instruction = .edgeReached
            return output
        case .spot(.step):
            return rightEdgeFound(
                reading, edgeX: Double(reading.position.x) + offsetFields * Double(heading.x),
                source: "line")
        default:
            return nil
        }
    }

    /// What the edge question is about now, for an answer that comes a moment later: the line at
    /// the cross (where it is, in guide fields), or the expected edge. nil when nothing is asked.
    var edgeQuestionSnapshot: EdgeQuestionSnapshot? {
        guard thresholds.fullCoverSlip else { return nil }
        if let line = repeatAsk, let heading = edgeHeading {
            return .line(
                point: CGPoint(x: heading.x * line.along, y: heading.y * line.along),
                angleDegrees: line.angle)
        }
        if lineEdge.atCross, let heading = edgeHeading {
            let offset = lineEdge.offsetFields ?? 0
            return .line(
                point: CGPoint(
                    x: Double(lastPosition.x) + offset * Double(heading.x),
                    y: Double(lastPosition.y) + offset * Double(heading.y)),
                angleDegrees: lineEdge.angleDegrees ?? 0)
        }
        if expectedEdgeAsking, let column = current, let edge = predictedEdge(for: column) {
            return .expected(edgeAlong: edge)
        }
        return nil
    }

    /// The helper's answer to a question captured earlier (`edgeQuestionSnapshot`): the edge it
    /// was about is accepted or rejected even if the line has since left the cross. The second
    /// value is whether it applied; it does not when the route has moved on (no leg, no heading).
    mutating func answerEdgeQuestion(
        _ snapshot: EdgeQuestionSnapshot, _ feedback: EdgeFeedback, _ reading: GuideReading
    ) -> (output: Output, applied: Bool) {
        guard thresholds.fullCoverSlip else { return (lastOutput, false) }
        switch (snapshot, feedback) {
        case (.expected(let edge), .yes):
            guard let column = current else { return (lastOutput, false) }
            expectedEdgeAsking = false
            guard
                let output = takeLineEdge(
                    reading, offsetFields: (edge - Double(reading.position.y)) * column.legDirection,
                    angleDegrees: 0, angleKnown: false)
            else { return (lastOutput, false) }
            lastOutput = output
            return (output, true)
        case (.expected, .no):
            guard current != nil else { return (lastOutput, false) }
            expectedEdgeAsking = false
            expectedAskDismissed = true
            notAnEdgeUntil = reading.seconds + thresholds.lineEdge.notAnEdgeSeconds
            lastOutput.instruction = .notAnEdge
            return (lastOutput, true)
        case (.line(let point, let angle), .yes), (.line(let point, let angle), .no):
            guard let heading = edgeHeading else { return (lastOutput, false) }
            // Where the edge is now relative to the view, along the heading.
            let offset =
                Double(point.x - reading.position.x) * Double(heading.x)
                + Double(point.y - reading.position.y) * Double(heading.y)
            if feedback == .yes {
                guard
                    let output = takeLineEdge(reading, offsetFields: offset, angleDegrees: angle)
                else { return (lastOutput, false) }
                lastOutput = output
                return (output, true)
            }
            edgeMemory.recordRejected(
                LineEdgeMemory.entry(
                    normal: heading, position: reading.position, offsetFields: offset,
                    angleDegrees: angle))
            lineEdge.reset()
            lineSeenAt = nil
            if let asked = repeatAsk { rejectedAlongs.append(asked.along) }
            resetEpisodes(keepingRejected: true)
            notAnEdgeUntil = reading.seconds + thresholds.lineEdge.notAnEdgeSeconds
            lastOutput.instruction = .notAnEdge
            return (lastOutput, true)
        case (_, .mark):
            return (lastOutput, false)
        }
    }

    /// The helper's answer about an edge in full-cover-slip mode. "Yes" takes the line that is
    /// attached and at the cross; "mark" takes an edge at the cross along `edgeHeading` (one the
    /// rule missed); "no" rejects the line for the rest of the leg or run and says to keep going.
    /// Anything that does not apply returns the last answer.
    mutating func userEdge(_ feedback: EdgeFeedback, _ reading: GuideReading) -> Output {
        guard thresholds.fullCoverSlip else { return lastOutput }
        if feedback != .mark, repeatAsk != nil, let snapshot = edgeQuestionSnapshot {
            // The repeated line's question: answered about the line's captured slide position.
            let result = answerEdgeQuestion(snapshot, feedback, reading)
            if result.applied { return result.output }
        }
        var output: Output?
        switch feedback {
        case .yes:
            if expectedEdgeAsking, !lineEdge.atCross, let column = current,
                let edge = predictedEdge(for: column)
            {
                // The helper accepts the predicted edge: the leg ends there.
                expectedEdgeAsking = false
                output = takeLineEdge(
                    reading, offsetFields: (edge - Double(reading.position.y)) * column.legDirection,
                    angleDegrees: 0, angleKnown: false)
                break
            }
            guard lineEdge.atCross else { return lastOutput }
            output = takeLineEdge(
                reading, offsetFields: lineEdge.offsetFields ?? 0,
                angleDegrees: lineEdge.angleDegrees ?? 0)
        case .mark:
            guard let along = markHeading else { return lastOutput }
            // The edge is where the accepted line is when one is near, not where the helper stood
            // (run C mark 2: the line was 0.38 field from the view).
            let lead = thresholds.lineEdge.lineLeadFields
            var offset = 0.0
            var seenLine = false
            if lineEdge.state != .none, let seen = lineEdge.offsetFields, abs(seen) <= lead {
                offset = seen
                seenLine = true
            }
            // A mark with no line near has no angle: straight columns follow, a flat limit.
            output = takeLineEdge(
                reading, offsetFields: offset, angleDegrees: lineEdge.angleDegrees ?? 0, along: along,
                angleKnown: seenLine && lineEdge.angleDegrees != nil)
        case .no:
            if expectedEdgeAsking {
                // Not the edge: carry on for the rest of this leg.
                expectedEdgeAsking = false
                expectedAskDismissed = true
                notAnEdgeUntil = reading.seconds + thresholds.lineEdge.notAnEdgeSeconds
                lastOutput.instruction = .notAnEdge
                return lastOutput
            }
            guard let heading = edgeHeading, lineEdge.state != .none,
                let offset = lineEdge.offsetFields
            else {
                return lastOutput
            }
            edgeMemory.recordRejected(
                LineEdgeMemory.entry(
                    normal: heading, position: reading.position, offsetFields: offset,
                    angleDegrees: lineEdge.angleDegrees ?? 0))
            lineEdge.reset()
            lineSeenAt = nil
            resetEpisodes(keepingRejected: true)
            notAnEdgeUntil = reading.seconds + thresholds.lineEdge.notAnEdgeSeconds
            lastOutput.instruction = .notAnEdge
        }
        if let output { lastOutput = output }
        return lastOutput
    }

    /// Full-cover-slip mode on a leg or a step right: a confirmed line ends the leg (or the
    /// route, on a step); a blank box after a step right is the right edge too, at rest; a line
    /// at the cross that was never seen to move with the slide asks to be proven. nil otherwise.
    private mutating func lineEdgeOutcome(
        _ kind: SpotKind, _ reading: GuideReading, target: CGPoint
    ) -> Output? {
        guard kind == .leg || kind == .step else { return nil }
        if kind == .step, rightEdgeSeen { return nil }
        if lineEdge.state == .confirmed,
            let output = takeLineEdge(
                reading, offsetFields: lineEdge.offsetFields ?? 0,
                angleDegrees: lineEdge.angleDegrees ?? 0)
        {
            return output
        }
        if kind == .leg, let line = repeatAsk, let column = current {
            // Asked about a line passed again and again: hold still, with the cross on the line.
            return Output(
                instruction: .edgeDetected,
                target: CGPoint(
                    x: columnX(column, at: line.along * column.legDirection),
                    y: line.along * column.legDirection), capture: nil)
        }
        if kind == .step, !rightEdgeSeen {
            if let since = emptyAheadSince,
                reading.seconds - since >= thresholds.emptyAheadSeconds - 1e-9
            {
                return rightEdgeFound(
                    reading, edgeX: Double(reading.position.x), source: "empty")
            }
            if candidateNow == .wholeBoxLowDetail, edgeReached(reading),
                reading.isStill(for: thresholds.confirmation.confirmSeconds)
            {
                return rightEdgeFound(
                    reading, edgeX: Double(reading.position.x), source: "empty")
            }
        }
        if lineEdge.needsProof(reading) {
            return Output(
                instruction: .checkEdge(toward: CGPoint(x: -heading.x, y: -heading.y)),
                target: target, capture: nil)
        }
        return nil
    }

    // MARK: Edges

    /// A whole-box low-detail edge, confirmed (overshot, now going back) or decided when detail
    /// came back after a long blur. Starts the way back for what the route was doing.
    /// - Parameter completeNow: finish the return on this reading, which is already on sample.
    private mutating func takeWholeBoxEdge(_ reading: GuideReading, completeNow: Bool) -> Output {
        switch phase {
        case .runToLeftEdge:
            edgesGoneBack += 1
            beginReturn(.leftEdge)
        case .spot(let kind):
            guard let target = alignment.target else { return plain(.aligned) }
            switch kind {
            case .leg, .edgeSpot:
                if kind == .leg { edgesGoneBack += 1 }
                beginReturn(.legEnd)
            case .step:
                beginReturn(.stepRight)
            case .inward, .recheckTravel:
                travelRetries += 1
                if travelRetries > thresholds.maxTravelRetries {
                    finish(reason: .sampleFinished)
                    return plain(.finished)
                }
                resumeTarget = (target, kind, false)
                beginReturn(.resume)
            }
        default:
            return plain(.aligned)
        }
        if completeNow, case .returning(let purpose) = phase {
            return completeReturn(purpose, reading)
        }
        return plain(goBack(reading))
    }

    /// Refocus; after `refocusAfterSeconds` of whole-box low detail that is not an edge, "still
    /// no detail", which decides nothing. The route stays where it is until detail returns.
    ///
    /// A stretch that began while the helper was moving normally, on the left edge run or a
    /// column leg, asks to step back and come forward again at once instead: the picture went
    /// blank under a helper who was not flicking or resting, which is what an edge does, and
    /// the whole-box arrival check decides when detail is back. After `refocusAfterSeconds` it
    /// is "still no detail" like any other (a real defocus is not cured by stepping back).
    private mutating func blurInstruction(_ reading: GuideReading) -> GuideInstruction {
        guard candidateNow == .wholeBoxLowDetail, let lowDetailSince,
            case .edgeGoBack(let toward) = goBack(reading)
        else { return .refocus }
        if reading.seconds - lowDetailSince > thresholds.refocusAfterSeconds {
            if longBlur == nil, let stretchStart { longBlur = stretchStart }
            rawDiagnostics.reason = "timeout_no_detail"
            return .stillNoDetail(toward: toward)
        }
        if stretchWasMoving, phase == .runToLeftEdge || phase == .spot(.leg) {
            rawDiagnostics.reason = "moving_onset"
            return .checkEdge(toward: toward)
        }
        return .refocus
    }

    private mutating func beginReturn(_ purpose: Purpose) {
        phase = .returning(purpose)
        longBlur = nil
        atTargetSince = nil
        lowDetailSince = nil
        detailSince = nil
        halfEdgeSince = nil
        confirmation.cancel()
    }

    /// While going back: the same as `goBack`, until low detail has lasted `refocusAfterSeconds`.
    private func returning(_ reading: GuideReading) -> GuideInstruction {
        let back = goBack(reading)
        if let lowDetailSince, case .edgeGoBack(let toward) = back,
            reading.seconds - lowDetailSince > thresholds.refocusAfterSeconds
        {
            return .stillNoDetail(toward: toward)
        }
        return back
    }

    /// Toward the last spot with sample. The position is frozen while the tracker is paused,
    /// so this is often about zero; then it is the way we came.
    private func goBack(_ reading: GuideReading) -> GuideInstruction {
        if let lastSample {
            let dx = Double(lastSample.x - reading.position.x)
            let dy = Double(lastSample.y - reading.position.y)
            if hypot(dx, dy) >= 0.1 { return .edgeGoBack(toward: CGPoint(x: dx, y: dy)) }
        }
        return .edgeGoBack(toward: CGPoint(x: -heading.x, y: -heading.y))
    }

    /// - Parameter edgeAtCentre: the left edge was found with the edge at the centre cross (the
    ///   half rule), so the column starts `columnInsetFields` inside it, toward the sample.
    ///   Coming back from a whole-box overshoot, the position is already on sample.
    private mutating func completeReturn(
        _ purpose: Purpose, _ reading: GuideReading, edgeAtCentre: Bool = false
    ) -> Output {
        switch purpose {
        case .leftEdge:
            let inset = edgeAtCentre ? thresholds.sideInsetFields : 0
            let columnX = Double(reading.position.x) + inset
            if isRecheckRun {
                isRecheckRun = false
                slipTiltDegrees = nil
                if let first = columns.first, columnX <= first.x - thresholds.columnSpacingFields {
                    return beginColumn(at: reading, firstLeg: -1, inset: inset)
                }
                return beginStep(from: columns.count - 1, reading)
            }
            return beginColumn(at: reading, firstLeg: -1, inset: inset)
        case .legEnd:
            return endLeg(reading)
        case .stepRight:
            return failProbe(reading)
        case .resume:
            guard let resumeTarget else { return plain(.aligned) }
            // `aim` starts the retries afresh; a resume is the same attempt, or a target that
            // always runs into the edge would be retried for ever.
            let retries = travelRetries
            aim(
                at: resumeTarget.point, from: reading.position, kind: resumeTarget.kind,
                holds: resumeTarget.holds)
            travelRetries = retries
            return spot(resumeTarget.kind, reading)
        }
    }

    // MARK: Columns

    /// A column starts at the return point, `inset` fields toward the sample: its x is there,
    /// and the first spot is at that x on the current row.
    private mutating func beginColumn(
        at reading: GuideReading, firstLeg: Double, inset: Double = 0
    ) -> Output {
        let x = Double(reading.position.x) + inset
        reachedColumn = false
        current = Column(
            number: columns.count + 1, x: x,
            minY: Double(reading.position.y), maxY: Double(reading.position.y),
            legDirection: firstLeg, gapsAtStart: reading.unconfirmedGaps,
            startY: Double(reading.position.y), slope: slipSlope)
        // The first spot may be here (inset 0): `aim` finds no direction then, so the view is sent
        // along the leg.
        if inset == 0 { heading = CGPoint(x: 0, y: firstLeg) }
        aim(at: CGPoint(x: x, y: reading.position.y), from: reading.position, kind: .leg, holds: true)
        return spot(.leg, reading)
    }

    private mutating func aim(at point: CGPoint, from start: CGPoint, kind: SpotKind, holds: Bool) {
        alignment.setTarget(point, from: start, holds: holds, axis: heading)
        phase = .spot(kind)
        approachingEdge = false
        spotLimitReason = ""
        // A low-detail stretch from the last spot says nothing about the way to this one.
        lowDetailSince = nil
        detailSince = nil
        halfEdgeSince = nil
        atTargetSince = nil
        longBlur = nil
        confirmation.cancel()
        travelRetries = 0
        let dx = Double(point.x - start.x)
        let dy = Double(point.y - start.y)
        if hypot(dx, dy) > 0.05 { heading = CGPoint(x: dx / hypot(dx, dy), y: dy / hypot(dx, dy)) }
    }

    private func isDuplicate(_ point: CGPoint) -> Bool {
        placements.contains {
            hypot(Double($0.position.x - point.x), Double($0.position.y - point.y))
                < thresholds.duplicateSpotFields
        }
    }

    /// The next spot along the column from `y`, skipping spots that are already captured.
    private func nextSpotY(from y: Double, direction: Double, column: Column) -> Double {
        var candidate = y
        for _ in 0..<400 {
            candidate += direction * thresholds.spotSpacingFields
            if !isDuplicate(CGPoint(x: columnX(column, at: candidate), y: candidate)) { break }
        }
        // Never beyond a recorded stage limit: the last spot of the leg is on it.
        if direction < 0, let top = limits.minY { candidate = max(candidate, top) }
        if direction > 0, let bottom = limits.maxY { candidate = min(candidate, bottom) }
        return candidate
    }

    /// Whether `y` is at the recorded limit of a leg going `direction` (-1 up, +1 down).
    private func isAtLimit(y: Double, direction: Double) -> Bool {
        let tolerance = thresholds.stageLimitToleranceFields
        if direction < 0, let top = limits.minY { return y <= top + tolerance }
        if direction > 0, let bottom = limits.maxY { return y >= bottom - tolerance }
        return false
    }

    private mutating func spot(_ kind: SpotKind, _ reading: GuideReading) -> Output {
        // Nearly empty ahead with no line for a moment: no more spots, the leg seeks the edge.
        if thresholds.fullCoverSlip, kind == .leg, !approachingEdge, let column = current,
            let since = legEmptySince,
            reading.seconds - since >= thresholds.legEmptyAheadSeconds - 1e-9
        {
            let ahead = Double(reading.position.y) + column.legDirection * thresholds.spotSpacingFields
            aim(
                at: CGPoint(x: columnX(column, at: ahead), y: ahead), from: reading.position,
                kind: .leg, holds: false)
            approachingEdge = true
            spotLimitReason = "empty_ahead"
        }
        guard let target = alignment.target else { return plain(.aligned) }
        // Keeps the blur stretch whatever happens below: `alignment.update` is not always reached.
        _ = alignment.warning(reading, allowsRefocus: false)
        if thresholds.fullCoverSlip, let output = lineEdgeOutcome(kind, reading, target: target) {
            return output
        }
        if let output = expectedEdgeOutcome(kind, reading, target: target) { return output }

        // A candidate edge must pass `EdgeConfirmation`; a blur is not an edge and the leg
        // carries on where it was.
        switch verdict {
        case .checking(let progress):
            return Output(instruction: .checkingEdge(progress: progress), target: target, capture: nil)
        case .blur:
            return Output(instruction: blurInstruction(reading), target: target, capture: nil)
        case .none, .confirmed:
            break
        }

        if verdict == .confirmed, candidateNow == .halfEdge {
            consumeConfirmation()
            edgesReached += 1
            halfEdgeSince = nil
            var output = endLeg(reading)
            output.instruction = .edgeReached
            return output
        }

        if verdict == .confirmed {
            consumeConfirmation()
            return takeWholeBoxEdge(reading, completeNow: false)
        }

        var instruction = alignment.update(reading)
        if thresholds.fullCoverSlip, kind == .leg, let column = current {
            instruction = edgeLeadInstruction(instruction, reading, legDirection: column.legDirection)
        }
        if thresholds.fullCoverSlip, kind == .leg || kind == .step, let heading = edgeHeading {
            let back = CGPoint(x: -heading.x, y: -heading.y)
            // Going back, aim AT the line (not the spot beyond it), and hold within the cross band.
            let lineAt = kind == .leg ? current.flatMap { legLinePoint(reading, column: $0) } : nil
            if lineEdge.state == .behind, instruction != .captured {
                return Output(
                    instruction: .edgeBehind(toward: back), target: lineAt ?? target, capture: nil)
            }
            if let lineAt, (lastSpot.map { spots[$0].count } ?? 0) >= 1, instruction != .captured,
                lineEdge.state == .ahead || lineEdge.state == .attached,
                abs(lineEdge.offsetFields ?? .infinity) <= thresholds.lineEdge.atCrossFields
            {
                return Output(instruction: .edgeDetected, target: lineAt, capture: nil)
            }
            if instruction == .refocus, let remembered = lineMemoryInstruction(reading, backward: back) {
                return Output(instruction: remembered, target: target, capture: nil)
            }
        }
        switch instruction {
        case .refocus, .slowDown, .tooFar, .otherWay, .missedSpot:
            return Output(instruction: instruction, target: target, capture: nil)
        default:
            break
        }
        if thresholds.fullCoverSlip, kind == .leg || kind == .step {
            switch instruction {
            case .move, .farAway, .aligned:
                if let until = notAnEdgeUntil, reading.seconds < until {
                    instruction = .notAnEdge
                } else if lineEdge.atCross {
                    instruction = .edgeDetected
                } else if instruction != .aligned, let heading = edgeHeading,
                    let remembered = lineMemoryInstruction(
                        reading, backward: CGPoint(x: -heading.x, y: -heading.y))
                {
                    instruction = remembered
                } else if instruction != .aligned, Self.isLowDetail(reading) {
                    instruction = .nothingToFollow
                } else if approachingEdge, kind == .leg {
                    instruction = .travel(direction: CGPoint(x: 0, y: current?.legDirection ?? 0))
                }
            default: break
            }
        }

        let reached = instruction == .captured || (!alignment.holdsTarget && alignment.isAtTarget)
        // Past the last ordinary spot there is nothing to capture: only the edge ends the leg.
        guard reached, !(approachingEdge && kind == .leg) else {
            return Output(instruction: instruction, target: target, capture: nil)
        }

        switch kind {
        case .leg:
            let placement = capture(reading)
            if let column = current {
                if isAtLimit(y: Double(target.y), direction: column.legDirection) {
                    // At the stage limit: the leg ends as at an edge, with no tap.
                    let next = finishLeg(reading)
                    return Output(instruction: .captured, target: next.target, capture: placement)
                }
                aimNextLegSpot(from: reading.position, column: column)
            }
            return Output(instruction: .captured, target: alignment.target, capture: placement)
        case .edgeSpot:
            let placement = capture(reading)
            let next = finishLeg(reading)
            return Output(instruction: .captured, target: next.target, capture: placement)
        case .step:
            let base = stepBase.map { columns[$0] }
            let direction = base?.endDirection ?? 1
            // Full-cover slip: a true zig-zag. The new column goes away from the edge the last one
            // ended on, and is ONE leg (it starts at an edge), so it ends at the opposite edge.
            let zigZag = thresholds.fullCoverSlip
            current = Column(
                number: columns.count + 1, x: Double(target.x), minY: Double(target.y),
                maxY: Double(target.y), legDirection: zigZag ? -direction : direction,
                legsDone: zigZag ? 1 : 0, gapsAtStart: reading.unconfirmedGaps,
                startY: Double(target.y), slope: slipSlope, isLast: lastColumnNext)
            lastColumnNext = false
            expectedAskDismissed = false
            probeIndex = 0
            let placement = alignment.holdsTarget ? capture(reading) : nil
            if let column = current { aimNextLegSpot(from: reading.position, column: column) }
            return Output(instruction: .captured, target: alignment.target, capture: placement)
        case .inward:
            if let step = pendingStepTarget {
                pendingStepTarget = nil
                aim(at: step, from: reading.position, kind: .step, holds: !isDuplicate(step))
            }
            return Output(instruction: .aligned, target: alignment.target, capture: nil)
        case .recheckTravel:
            phase = .runToLeftEdge
            isRecheckRun = true
            heading = CGPoint(x: -1, y: 0)
            leftEdgeY = Double(reading.position.y)
            lowDetailSince = nil
            detailSince = nil
            return plain(.travel(direction: CGPoint(x: -1, y: 0)))
        }
    }

    private mutating func capture(_ reading: GuideReading) -> FramePlacement? {
        guard let column = current else { return nil }
        let placement = FramePlacement(
            column: column.number, order: placements.count + 1, position: reading.position,
            uncertain: reading.unconfirmedGaps > column.gapsAtStart)
        placements.append(placement)
        if column.number == 1 { countingStarted = true }
        return placement
    }

    // MARK: Ending a leg

    private mutating func endLeg(_ reading: GuideReading) -> Output {
        let nearest = placements.map {
            hypot(Double($0.position.x - reading.position.x), Double($0.position.y - reading.position.y))
        }.min()
        if (nearest ?? .infinity) > thresholds.edgeSpotMinFields {
            aim(at: reading.position, from: reading.position, kind: .edgeSpot, holds: true)
            return spot(.edgeSpot, reading)
        }
        return finishLeg(reading)
    }

    @discardableResult
    private mutating func finishLeg(_ reading: GuideReading) -> Output {
        edgeMemory.clearRejected()
        resetEpisodes()
        expectedEdgeAsking = false
        expectedAskDismissed = false
        guard var column = current else { return plain(.aligned) }
        column.legsDone += 1
        column.endDirection = column.legDirection
        if column.legsDone == 1 {
            column.legDirection = -column.legDirection
            column.edgeY = nil
            current = column
            aimNextLegSpot(from: reading.position, column: column)
            return Output(instruction: .aligned, target: alignment.target, capture: nil)
        }
        let last = placements.last { $0.column == column.number }
        column.endSpot = last?.position ?? reading.position
        current = column
        columns.append(column)
        return finishColumn(column, reading)
    }

    private mutating func finishColumn(_ column: Column, _ reading: GuideReading) -> Output {
        if pendingEnd {
            endNow()
            return plain(.finished)
        }
        if column.isLast {
            // The last column keeps how its edge was found; one placed from the prediction says so.
            if rightEdgeSource.isEmpty { rightEdgeSource = "predicted" }
            finish(reason: .rightEdge)
            return plain(.finished)
        }
        let leftmost = columns.map(\.x).min() ?? column.x
        let middle = (column.minY + column.maxY) / 2
        let allowedRechecks = thresholds.fullCoverSlip ? 0 : thresholds.maxLeftRechecks
        if column.x <= leftmost, rechecks < allowedRechecks,
            abs(middle - leftEdgeY) > thresholds.recheckLeftFields
        {
            rechecks += 1
            aim(
                at: CGPoint(x: column.x, y: middle), from: reading.position, kind: .recheckTravel,
                holds: false)
            return Output(instruction: .aligned, target: alignment.target, capture: nil)
        }
        return beginStep(from: columns.count - 1, reading)
    }

    // MARK: Stepping right

    private mutating func beginStep(from index: Int, _ reading: GuideReading) -> Output {
        stepBase = index
        probeIndex = 0
        rightEdgeSeen = false
        let base = columns[index]
        // A slanted column's next one is `columnSpacingFields` away measured across the slant.
        let stepRow = stepY(base)
        var x =
            columnX(base, at: stepRow) + thresholds.columnSpacingFields / cos(atan(-base.slope))
        if let right = predictedRightEdgeX() {
            // A step that would cross the predicted right edge is shortened to the edge less the
            // inset and is the last column; too close to the column just done, there is none.
            let farthest = right - thresholds.sideInsetFields
            if x > farthest {
                rightEdgeX = right
                rightEdgeSource = "predicted"
                if farthest - base.x < thresholds.lastColumnMinFields {
                    finish(reason: .rightEdge)
                    return plain(.finished)
                }
                x = farthest
                lastColumnNext = true
            }
        }
        let target = CGPoint(x: x, y: stepRow)
        if let right = limits.maxX, target.x > right + thresholds.stageLimitToleranceFields {
            finish(reason: .stageLimit)
            return plain(.finished)
        }
        aim(at: target, from: reading.position, kind: .step, holds: !isDuplicate(target))
        return Output(instruction: .aligned, target: target, capture: nil)
    }

    /// Where a step right from `base` lands along the leg axis: the column's end spot, or after a
    /// confirmed or marked edge, the edge moved `sideInsetFields` inward (away from it, back
    /// toward the sample) so the next column's first spot is not ON the edge line.
    private func stepY(_ base: Column) -> Double {
        guard thresholds.fullCoverSlip, let edgeY = base.edgeY else { return Double(base.endSpot.y) }
        return edgeY - base.endDirection * thresholds.sideInsetFields
    }

    /// A step right landed on blank: back to the sample, inward along the previous column,
    /// and step again from there.
    private mutating func failProbe(_ reading: GuideReading) -> Output {
        guard let index = stepBase else { return plain(.aligned) }
        if thresholds.fullCoverSlip {
            // No inward probing: the sample fills the cover slip, so blank here is its right edge.
            rightEdgeSource = "probe"
            finish(reason: .rightEdge)
            return plain(.finished)
        }
        failedProbes += 1
        let base = columns[index]
        probeIndex += thresholds.probeStrideSpots
        let reach = Double(probeIndex) * thresholds.spotSpacingFields
        if reach > (base.maxY - base.minY) + 1e-6 {
            finish(reason: .sampleFinished)
            return plain(.finished)
        }
        let y = Double(base.endSpot.y) - base.endDirection * reach
        pendingStepTarget = CGPoint(x: base.x + thresholds.columnSpacingFields, y: y)
        aim(at: CGPoint(x: base.x, y: y), from: reading.position, kind: .inward, holds: false)
        return Output(instruction: .aligned, target: alignment.target, capture: nil)
    }
}
