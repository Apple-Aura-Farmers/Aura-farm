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
    /// How far column 1 sits inside the left edge, toward the sample, when the edge was found
    /// at the centre cross. The box is 1 field wide, so 0.5 puts its edge on the cover slip's
    /// edge; 0.6 leaves a little margin for a skewed stage. PLACEHOLDER: not calibrated.
    var columnInsetFields: Double = 0.6
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
    /// What the last reading made of the edge conditions, for the CSV.
    private(set) var diagnostics = EdgeDiagnostics()

    init(thresholds: GuidedSweepThresholds = GuidedSweepThresholds()) {
        self.thresholds = thresholds
        alignment = SpotAlignment(thresholds: thresholds.alignment)
        confirmation = EdgeConfirmation(
            thresholds: thresholds.confirmation, halfCut: thresholds.halfLowDetailBelowSharpness)
    }

    var isFinished: Bool { phase == .finished }
    var columnNumber: Int { current?.number ?? 0 }

    mutating func finish(reason: SweepFinishReason) {
        phase = .finished
        finishReason = finishReason ?? reason
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
        lastOutput = advance(reading)
        return lastOutput
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
            rawReason = "corner"
        }
        return true
    }

    /// The x positions the route knows an edge at: the left edge column 1 was set inside, and
    /// the recorded stage limits.
    var knownEdgeXs: [Double] {
        var edges = [limits.minX, limits.maxX].compactMap { $0 }
        if let first = columns.first ?? current { edges.append(first.x - thresholds.columnInsetFields) }
        return edges
    }

    /// Whether the side half with less detail lies toward a known edge within reach of the column.
    /// False without the side's screen direction.
    private func lowSideFacesKnownEdge(_ reading: GuideReading, lowIsA: Bool) -> Bool {
        guard let direction = reading.sideADirection else { return false }
        let towardLow = lowIsA ? Double(direction.x) : -Double(direction.x)
        let x = current?.x ?? Double(reading.position.x)
        return knownEdgeXs.contains {
            abs(x - $0) <= thresholds.sideEdgeReachFields && ($0 - x) * towardLow > 0
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
        longBlur = nil
        let returned = reading.blankReturnCount > pending.returns
        let moved = hypot(
            Double(reading.position.x - pending.position.x),
            Double(reading.position.y - pending.position.y))
        if !returned || (reading.lastBlankReturn == .matched && moved <= thresholds.sameSpotFields) {
            // Blur: carry on where it was, nothing was decided.
            lowDetailSince = nil
            detailSince = nil
            confirmation.cancel()
            verdict = .none
            rawReason = "same_spot"
            return nil
        }
        diagnostics = EdgeDiagnostics(candidate: "whole_box", verdict: "confirmed", reason: "moved")
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
        diagnostics = EdgeDiagnostics(
            candidate: candidate.csvName, verdict: verdict.csvName, reason: reason)
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
            diagnostics.reason = "timeout_no_detail"
            return .stillNoDetail(toward: toward)
        }
        if stretchWasMoving, phase == .runToLeftEdge || phase == .spot(.leg) {
            diagnostics.reason = "moving_onset"
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
            let inset = edgeAtCentre ? thresholds.columnInsetFields : 0
            let columnX = Double(reading.position.x) + inset
            if isRecheckRun {
                isRecheckRun = false
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
        current = Column(
            number: columns.count + 1, x: x,
            minY: Double(reading.position.y), maxY: Double(reading.position.y),
            legDirection: firstLeg, gapsAtStart: reading.unconfirmedGaps)
        aim(at: CGPoint(x: x, y: reading.position.y), from: reading.position, kind: .leg, holds: true)
        if inset == 0 {
            // The first spot is here, so `aim` found no direction: the view is sent along the leg.
            heading = CGPoint(x: 0, y: firstLeg)
        }
        return spot(.leg, reading)
    }

    private mutating func aim(at point: CGPoint, from start: CGPoint, kind: SpotKind, holds: Bool) {
        alignment.setTarget(point, from: start, holds: holds)
        phase = .spot(kind)
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
    private func nextSpotY(from y: Double, direction: Double, x: Double) -> Double {
        var candidate = y
        for _ in 0..<400 {
            candidate += direction * thresholds.spotSpacingFields
            if !isDuplicate(CGPoint(x: x, y: candidate)) { break }
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
        guard let target = alignment.target else { return plain(.aligned) }
        // Keeps the blur stretch whatever happens below: `alignment.update` is not always reached.
        _ = alignment.warning(reading, allowsRefocus: false)

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

        let instruction = alignment.update(reading)
        switch instruction {
        case .refocus, .slowDown, .tooFar, .otherWay:
            return Output(instruction: instruction, target: target, capture: nil)
        default:
            break
        }

        let reached = instruction == .captured || (!alignment.holdsTarget && alignment.isAtTarget)
        guard reached else { return Output(instruction: instruction, target: target, capture: nil) }

        switch kind {
        case .leg:
            let placement = capture(reading)
            if let column = current {
                if isAtLimit(y: Double(target.y), direction: column.legDirection) {
                    // At the stage limit: the leg ends as at an edge, with no tap.
                    let next = finishLeg(reading)
                    return Output(instruction: .captured, target: next.target, capture: placement)
                }
                let y = nextSpotY(
                    from: Double(reading.position.y), direction: column.legDirection, x: column.x)
                aim(at: CGPoint(x: column.x, y: y), from: reading.position, kind: .leg, holds: true)
            }
            return Output(instruction: .captured, target: alignment.target, capture: placement)
        case .edgeSpot:
            let placement = capture(reading)
            let next = finishLeg(reading)
            return Output(instruction: .captured, target: next.target, capture: placement)
        case .step:
            let base = stepBase.map { columns[$0] }
            let direction = base?.endDirection ?? 1
            current = Column(
                number: columns.count + 1, x: Double(target.x), minY: Double(target.y),
                maxY: Double(target.y), legDirection: direction, gapsAtStart: reading.unconfirmedGaps)
            probeIndex = 0
            let placement = alignment.holdsTarget ? capture(reading) : nil
            if let column = current {
                let y = nextSpotY(
                    from: Double(reading.position.y), direction: column.legDirection, x: column.x)
                aim(at: CGPoint(x: column.x, y: y), from: reading.position, kind: .leg, holds: true)
            }
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
        guard var column = current else { return plain(.aligned) }
        column.legsDone += 1
        column.endDirection = column.legDirection
        if column.legsDone == 1 {
            column.legDirection = -column.legDirection
            current = column
            let y = nextSpotY(from: Double(reading.position.y), direction: column.legDirection, x: column.x)
            aim(at: CGPoint(x: column.x, y: y), from: reading.position, kind: .leg, holds: true)
            return Output(instruction: .aligned, target: alignment.target, capture: nil)
        }
        let last = placements.last { $0.column == column.number }
        column.endSpot = last?.position ?? reading.position
        current = column
        columns.append(column)
        return finishColumn(column, reading)
    }

    private mutating func finishColumn(_ column: Column, _ reading: GuideReading) -> Output {
        let leftmost = columns.map(\.x).min() ?? column.x
        let middle = (column.minY + column.maxY) / 2
        if column.x <= leftmost, rechecks < thresholds.maxLeftRechecks,
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
        let base = columns[index]
        let target = CGPoint(
            x: base.x + thresholds.columnSpacingFields, y: Double(base.endSpot.y))
        if let right = limits.maxX, target.x > right + thresholds.stageLimitToleranceFields {
            finish(reason: .stageLimit)
            return plain(.finished)
        }
        aim(at: target, from: reading.position, kind: .step, holds: !isDuplicate(target))
        return Output(instruction: .aligned, target: target, capture: nil)
    }

    /// A step right landed on blank: back to the sample, inward along the previous column,
    /// and step again from there.
    private mutating func failProbe(_ reading: GuideReading) -> Output {
        guard let index = stepBase else { return plain(.aligned) }
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
