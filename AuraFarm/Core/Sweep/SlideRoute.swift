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

    private var alignment: SpotAlignment
    private var columns: [Column] = []
    private var current: Column?
    private var lastSample: CGPoint?
    /// When the current unbroken run of low-detail readings began.
    private var lowDetailSince: Double?
    /// When the run of detail readings that may end the stretch began.
    private var detailSince: Double?
    private var heading = CGPoint(x: -1, y: 0)
    private var leftEdgeY = 0.0
    private var isRecheckRun = false
    private var stepBase: Int?
    private var pendingStepTarget: CGPoint?
    private var resumeTarget: (point: CGPoint, kind: SpotKind, holds: Bool)?
    private var travelRetries = 0

    init(thresholds: GuidedSweepThresholds = GuidedSweepThresholds()) {
        self.thresholds = thresholds
        alignment = SpotAlignment(thresholds: thresholds.alignment)
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
        if Self.isLowDetail(reading) {
            lowDetailSince = lowDetailSince ?? reading.seconds
            detailSince = nil
        } else if lowDetailSince != nil {
            detailSince = detailSince ?? reading.seconds
            if reading.seconds - (detailSince ?? reading.seconds) >= thresholds.edgeRecoverySeconds - 1e-9 {
                lowDetailSince = nil
                detailSince = nil
            }
        }

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

    private static func isOnSample(_ reading: GuideReading) -> Bool {
        reading.tracking == .tracking && (reading.viewClass == .sample || reading.viewClass == .thin)
    }

    /// Too little detail to follow, whatever the class: blank glass, blur, dark, or the tracker
    /// paused (NO DETAIL). On soil the sample background is as bright as the glass outside the
    /// cover slip, so outside reads as blurry, not blank; all of these mean the edge.
    private static func isLowDetail(_ reading: GuideReading) -> Bool {
        reading.tracking == .paused || [.blank, .blurry, .dark].contains(reading.viewClass)
    }

    /// Low detail has lasted `edgeSeconds`: this is the edge.
    private func edgeReached(_ reading: GuideReading) -> Bool {
        guard Self.isLowDetail(reading), let lowDetailSince else { return false }
        return reading.seconds - lowDetailSince >= thresholds.edgeSeconds - 1e-9
    }

    private func plain(_ instruction: GuideInstruction) -> Output {
        Output(instruction: instruction, target: nil, capture: nil)
    }

    // MARK: Left edge

    private mutating func runToLeftEdge(_ reading: GuideReading) -> Output {
        if edgeReached(reading) {
            beginReturn(.leftEdge)
            return plain(goBack(reading))
        }
        if let warning = alignment.warning(reading, allowsRefocus: false) { return plain(warning) }
        return plain(.travel(direction: CGPoint(x: -1, y: 0)))
    }

    // MARK: Edges

    private mutating func beginReturn(_ purpose: Purpose) {
        phase = .returning(purpose)
        lowDetailSince = nil
        detailSince = nil
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

    private mutating func completeReturn(_ purpose: Purpose, _ reading: GuideReading) -> Output {
        switch purpose {
        case .leftEdge:
            let edgeX = Double(reading.position.x)
            if isRecheckRun {
                isRecheckRun = false
                if let first = columns.first,
                    edgeX <= first.x - thresholds.columnSpacingFields
                {
                    return beginColumn(at: reading, firstLeg: -1)
                }
                return beginStep(from: columns.count - 1, reading)
            }
            return beginColumn(at: reading, firstLeg: -1)
        case .legEnd:
            return endLeg(reading)
        case .stepRight:
            return failProbe(reading)
        case .resume:
            guard let resumeTarget else { return plain(.aligned) }
            aim(
                at: resumeTarget.point, from: reading.position, kind: resumeTarget.kind,
                holds: resumeTarget.holds)
            return spot(resumeTarget.kind, reading)
        }
    }

    // MARK: Columns

    /// A column starts at the return point: its x is where we are, and the first spot is here.
    private mutating func beginColumn(at reading: GuideReading, firstLeg: Double) -> Output {
        current = Column(
            number: columns.count + 1, x: Double(reading.position.x),
            minY: Double(reading.position.y), maxY: Double(reading.position.y),
            legDirection: firstLeg, gapsAtStart: reading.unconfirmedGaps)
        aim(at: reading.position, from: reading.position, kind: .leg, holds: true)
        return spot(.leg, reading)
    }

    private mutating func aim(at point: CGPoint, from start: CGPoint, kind: SpotKind, holds: Bool) {
        alignment.setTarget(point, from: start, holds: holds)
        phase = .spot(kind)
        // A low-detail stretch from the last spot says nothing about the way to this one.
        lowDetailSince = nil
        detailSince = nil
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
        return candidate
    }

    private mutating func spot(_ kind: SpotKind, _ reading: GuideReading) -> Output {
        guard let target = alignment.target else { return plain(.aligned) }

        if edgeReached(reading) {
            switch kind {
            case .leg, .edgeSpot:
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
            return plain(goBack(reading))
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
