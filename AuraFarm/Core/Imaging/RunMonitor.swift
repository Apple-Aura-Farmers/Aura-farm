import CoreGraphics
import CoreVideo
import Foundation

enum RunMonitorState: Equatable {
    case ok, pausedAlignment, pausedFocus

    /// A short word for the CSV.
    var csvName: String {
        switch self {
        case .ok: "ok"
        case .pausedAlignment: "paused_alignment"
        case .pausedFocus: "paused_focus"
        }
    }

    /// The route's pause reason, nil while running.
    var pauseReason: GuidePauseReason? {
        switch self {
        case .ok: nil
        case .pausedAlignment: .alignment
        case .pausedFocus: .focus
        }
    }
}

/// The numbers `RunMonitor` decides with. Data, not logic. All PLACEHOLDER, deliberately slow
/// to pause and slower to trust: a pause must not fire on a knock or a sample that is merely
/// plain. Calibrate from the movement CSV's `monitor_state`, `focus_index`, `focus_baseline`,
/// `circle_shift_r` and `circle_radius_change` columns.
struct RunMonitorThresholds {
    // Alignment, GEOMETRY ONLY: the sample's content would trip evenness and glare.
    /// The circle's centre moved this share of its radius from the confirmed one.
    var lostCentreShiftShareOfRadius: Double = 0.18
    /// The circle's radius changed by this share.
    var lostRadiusChange: Double = 0.15
    var lostMinRoundness: Double = 0.70
    /// Lost (a clipped circle, no circle, or the limits above) for this long without a break.
    var lostSeconds: Double = 3.0
    /// Back: within these of the confirmed circle, for `backSeconds`.
    var backCentreShiftShareOfRadius: Double = 0.06
    var backRadiusChange: Double = 0.05
    var backSeconds: Double = 1.0

    // Focus. The focus index is the box's Laplacian variance at step 2 over step 6: fine detail
    // fades first when defocused, so the ratio falls whatever the amount of sample.
    var pauseBelowShareOfBaseline: Double = 0.6
    var pauseSeconds: Double = 2.5
    var resumeAtShareOfBaseline: Double = 0.8
    /// PLACEHOLDER: raised from 1.0 after Run 6, where blurry views resumed too early.
    var resumeSeconds: Double = 1.5
    /// This share of the readings since the picture became sharp must be sharp and still: one
    /// reading that flickers to blurry does not start the count again. PLACEHOLDER.
    var resumeGoodShare: Double = 0.8
    /// A pause for focus also needs box sharpness at this share of its recent peak. The view
    /// hardly changes during a pause, so sharpness there is comparable. (The index is not: one
    /// noisy reading of 0.728 against a baseline of 0.324 could never be reached again.)
    /// PLACEHOLDER: in the 22 Nov runs' 12 pauses the blurry part read 0.3 of the sharp part.
    var resumeShareOfSharpnessPeak: Double = 0.5
    /// The peak looks back this far, so one that cannot be reached again is forgotten.
    var peakWindowSeconds: Double = 10
    /// Sharpness is the median of this many readings, so one spike is not a peak.
    var peakSmoothing = 5
    /// And only of readings this recent: after a gap (dark, lost, moving) older ones would come
    /// back as a fresh peak. Long enough for `peakSmoothing` readings at a slow frame rate.
    var smoothingSeconds: Double = 2
    /// `peakIndex` ignores the first part of a pause: the picture is still settling. PLACEHOLDER.
    var peakIgnoreSeconds: Double = 0.5
    /// Hint "try the other way": this long into the pause, under `hintOtherWayShare` of the
    /// starting index, and the peak never rose above it. PLACEHOLDER.
    var hintOtherWaySeconds: Double = 3.0
    var hintOtherWayShare: Double = 0.8
    /// With no baseline from setup: the median of this many seconds of eligible readings.
    var baselineSeconds: Double = 3.0
    /// A real defocus: detail lost while STILL. The readings with detail this far back give the
    /// "before" (matches `GuidedSweepThresholds.checkEdgeLookbackSeconds`). PLACEHOLDER.
    var stillOnsetLookbackSeconds: Double = 0.5
    /// The low-detail stretch's median box sharpness must be at or under this share of the
    /// lookback's. PLACEHOLDER: a real defocus drops far more; a thin patch flickering around
    /// the detail limit (Test 4 soil: 17 to 150 against 200 to 400) does not count.
    var detailDropShare: Double = 0.5

    // Focus, second signal. The focus index alone paused a run for 40% of its time on sharp
    // frames: it reads 0.15 to 0.59 on sharp frames depending on how much sample is in view.
    // Box sharpness is judged against the run's own recent sharpness instead.
    /// A pause also needs box sharpness under this share of the reference. PLACEHOLDER; source:
    /// the 17 Nov device runs. Run A's real pauses read 585 against a reference of 2244 (0.26);
    /// Run B's false pauses read 2105 against 1659 (1.27).
    var sharpnessPauseShare: Double = 0.5
    /// The reference is the median box sharpness over this many seconds of eligible readings.
    /// PLACEHOLDER.
    var referenceSeconds: Double = 20
    /// Until the reference holds this many seconds, the sharpness check is not made, so the start
    /// of a run behaves as before. PLACEHOLDER.
    var referenceMinimumSeconds: Double = 5
    /// A pause also ends when box sharpness is back to this share of the reference for
    /// `resumeSeconds`. PLACEHOLDER.
    var sharpnessResumeShare: Double = 0.8
    /// The focus index is read a few times a second. If none has arrived for longer than this,
    /// the counts are cleared when the next one does, so a countdown cannot carry across a long
    /// gap (tracking lost for a while). PLACEHOLDER: three times the reading interval.
    var focusReadingGapSeconds: Double = 1.0
}

/// A run of readings without detail, judged against the detail readings just before it.
private struct LowDetailStretch {
    var beforeStill: Bool
    var beforeMedian: Double?
    var sharpness: [Double] = []
}

/// Watches a run for the phone moving off the eyepiece and for the picture going out of focus,
/// so the guide can pause until it is back. Alignment wins when both apply. Pure: the caller
/// measures and feeds readings in time order.
///
/// Focus only counts while tracking with a view class of sample or thin; other readings neither
/// pause nor resume (edges and blank glass are the route's job) and clear any count in
/// progress. One exception: detail lost while the slide was STILL (see `isStillOnset`) is focus
/// or a bump, not an edge, since an edge can only be reached by moving.
struct RunMonitor {
    var thresholds: RunMonitorThresholds

    private(set) var state = RunMonitorState.ok
    /// The focus index the run is compared with; nil until known.
    private(set) var focusBaseline: Double?
    /// The latest centre shift (share of the confirmed radius) and radius change, for the CSV.
    private(set) var circleShift: Double?
    private(set) var circleRadiusChange: Double?

    private var focusLow = false
    private var stillOnset = false
    private var onsetSince: Double?
    private var detailHistory: [(seconds: Double, isStill: Bool, sharpness: Double?)] = []
    private var stretch: LowDetailStretch?
    private var badSince: Double?
    private var goodSince: Double?
    private var lowSince: Double?
    private var highSince: Double?
    private var baselineSamples: [(seconds: Double, value: Double)] = []
    /// Box sharpness of eligible readings while the monitor was OK, stamped on `referenceClock`,
    /// which only runs while it is OK: a long pause does not age the reference away.
    private var sharpnessHistory: [(seconds: Double, value: Double)] = []
    private var referenceClock = 0.0
    private var lastUpdateSeconds: Double?
    /// The latest focus index of a view with detail; nil once older than the gap. While paused
    /// it stands in on the frames between readings.
    private var lastIndex: (seconds: Double, value: Double)?
    /// When the last focus reading arrived, for the gap guard.
    private var lastFocusReadingAt: Double?
    /// The median of `sharpnessHistory`, once it spans `referenceMinimumSeconds`; for the CSV.
    private(set) var sharpnessReference: Double?
    /// The latest box sharpness over the reference; nil without either.
    private(set) var sharpnessShare: Double?
    /// Why the run is paused: "index_and_sharpness", "detail_lost" or "alignment"; empty while ok.
    private(set) var pauseCause = ""
    /// While paused for focus: the latest reading counts as sharp (moving or not). The dial's
    /// green zone and the resume both go by this.
    private(set) var isSharp = false
    /// The highest focus index among still detail readings in this pause (not the first
    /// `peakIgnoreSeconds`), for the CSV and the hint; nil outside a pause or before one.
    private(set) var peakIndex: Double?
    /// Set on the update that ended a pause for focus by itself: the numbers for the CSV.
    private(set) var resumeNote = ""
    private var latestIndex: Double?
    private var startIndex: Double?
    private var pauseStartedAt: Double?
    private var goodCount = 0
    private var readingCount = 0
    /// The latest still readings' box sharpness in this pause, and the medians with detail.
    private var recentSharpness: [(seconds: Double, value: Double)] = []
    private var sharpnessPeaks: [(seconds: Double, value: Double)] = []

    init(thresholds: RunMonitorThresholds = RunMonitorThresholds()) {
        self.thresholds = thresholds
    }

    /// - Parameters:
    ///   - alignment: this frame's `AlignmentMeasure` reading; nil on a frame it was not run on.
    ///   - confirmedCircle: the field circle the run started with; nil compares only the shape.
    ///   - focusIndex: the focus index of the registration box; nil when not measured.
    ///   - isStill: the helper is not moving the slide (the same signal as `GuideReading.isStill`).
    ///     Moving smears the picture, so only still readings count towards focus.
    ///   - boxSharpness: the registration box's sharpness (the tracker's); nil when not measured.
    @discardableResult
    mutating func update(
        alignment: AlignmentReading?, confirmedCircle: FieldCircle?, focusIndex: Double?,
        boxSharpness: Double? = nil, viewClass: ViewClass, tracking: TrackingState,
        isStill: Bool = true, seconds: Double
    ) -> RunMonitorState {
        if let last = lastUpdateSeconds, state == .ok { referenceClock += min(max(seconds - last, 0), 1) }
        lastUpdateSeconds = seconds
        resumeNote = ""
        if let alignment { updateAlignment(alignment, confirmedCircle, seconds) }
        defer { if state == .ok { pauseCause = "" } }
        guard state != .pausedAlignment else {
            pauseCause = "alignment"
            focusLow = false
            stretch = nil
            stillOnset = false
            onsetSince = nil
            return state
        }
        updateFocus(focusIndex, boxSharpness, viewClass, tracking, isStill, seconds)
        return state
    }

    /// The latest still, eligible focus reading is below `pauseBelowShareOfBaseline` of the
    /// baseline, so a spot should not be captured yet. False without a baseline, after a moving or
    /// ineligible reading, and while paused for alignment.
    var isFocusLow: Bool { focusLow && state != .pausedAlignment }

    /// A stretch without detail began while still, after detail that was far sharper: focus or a
    /// bump, not an edge. For the CSV.
    var isStillOnset: Bool { stillOnset && state != .pausedAlignment }

    /// While paused for focus: which way to turn, from how the index has moved since the pause.
    var focusHint: String? {
        guard state == .pausedFocus, !isSharp, let began = pauseStartedAt,
            let now = lastUpdateSeconds
        else { return nil }
        if !isNearSharpnessPeak { return "Turned past focus: turn back a little" }
        guard let start = startIndex, let current = latestIndex else { return nil }
        if now - began >= thresholds.hintOtherWaySeconds,
            current < thresholds.hintOtherWayShare * start, (peakIndex ?? 0) <= start
        {
            return "Try turning the other way"
        }
        return nil
    }

    /// The box is about as sharp as it has recently been in this pause; true without a peak.
    private var isNearSharpnessPeak: Bool {
        guard let peak = sharpnessPeaks.map(\.value).max(),
            let current = Self.median(recentSharpness.map(\.value))
        else { return true }
        return current >= thresholds.resumeShareOfSharpnessPeak * peak
    }

    private mutating func beginFocusPause(_ now: Double) {
        endFocusPause()
        pauseStartedAt = now
        startIndex = latestIndex
    }

    private mutating func endFocusPause() {
        pauseStartedAt = nil
        startIndex = nil
        peakIndex = nil
        isSharp = false
        lastIndex = nil
        recentSharpness = []
        sharpnessPeaks = []
    }

    /// The hand takes over: a pause for focus ends, and every focus count and low-detail
    /// stretch in progress is dropped. The baseline is kept (the manual resume measures it again;
    /// this one must not, the view comes back as it was). An alignment pause stays, and an
    /// alignment loss is still seen afterwards.
    mutating func endFocusPauseForHand() {
        if state == .pausedFocus {
            state = .ok
            endFocusPause()
            pauseCause = ""
        }
        clearFocusCounts()
        stretch = nil
        stillOnset = false
        onsetSince = nil
        detailHistory = []
    }

    /// "Resume anyway": back to running at once, and the baseline measured again from the next
    /// `baselineSeconds` of eligible readings. For a pause for focus only; the sharpness reference
    /// is kept.
    mutating func resumeManually() {
        guard state == .pausedFocus else { return }
        state = .ok
        endFocusPause()
        pauseCause = ""
        stretch = nil
        stillOnset = false
        onsetSince = nil
        setFocusBaseline(nil)
    }

    /// The picture stalled blurry for long enough that the caller says so: the same pause for
    /// focus as the monitor's own, which resumes by the same rules. Does nothing unless running.
    @discardableResult
    mutating func pauseForStall() -> Bool {
        guard state == .ok else { return false }
        state = .pausedFocus
        beginFocusPause(lastUpdateSeconds ?? 0)
        pauseCause = "stall"
        clearFocusCounts()
        stretch = nil
        stillOnset = false
        onsetSince = nil
        return true
    }

    /// Sets the focus index the run is compared with (from setup's focus step), or nil to
    /// collect it from the first readings.
    mutating func setFocusBaseline(_ value: Double?) {
        focusBaseline = value
        baselineSamples = []
        lowSince = nil
        highSince = nil
    }

    /// Back to running, every count cleared. The baseline is kept; clear it with
    /// `setFocusBaseline(nil)`.
    mutating func reset() {
        self = RunMonitor(thresholds: thresholds).keeping(focusBaseline)
    }

    private func keeping(_ baseline: Double?) -> RunMonitor {
        var copy = self
        copy.focusBaseline = baseline
        return copy
    }

    // MARK: Alignment

    private mutating func updateAlignment(
        _ reading: AlignmentReading, _ confirmed: FieldCircle?, _ now: Double
    ) {
        var shift: Double?
        var radius: Double?
        if let circle = reading.circle, reading.found, let confirmed, confirmed.radius > 0 {
            shift =
                hypot(
                    Double(circle.centre.x - confirmed.centre.x),
                    Double(circle.centre.y - confirmed.centre.y)) / confirmed.radius
            radius = abs(circle.radius - confirmed.radius) / confirmed.radius
        }
        circleShift = shift
        circleRadiusChange = radius

        let shapeFine =
            reading.found && reading.clippedSides.isEmpty
            && (reading.roundness ?? 0) >= thresholds.lostMinRoundness
        let bad =
            !shapeFine || (shift ?? 0) > thresholds.lostCentreShiftShareOfRadius
            || (radius ?? 0) > thresholds.lostRadiusChange
        let good =
            shapeFine && (shift ?? 0) <= thresholds.backCentreShiftShareOfRadius
            && (radius ?? 0) <= thresholds.backRadiusChange

        badSince = bad ? (badSince ?? now) : nil
        goodSince = good ? (goodSince ?? now) : nil
        switch state {
        case .pausedAlignment:
            if let goodSince, now - goodSince >= thresholds.backSeconds - 1e-9 {
                state = .ok
                clearFocusCounts()
            }
        case .ok, .pausedFocus:
            if let badSince, now - badSince >= thresholds.lostSeconds - 1e-9 {
                state = .pausedAlignment
                pauseCause = "alignment"
                goodSince = nil
                clearFocusCounts()
            }
        }
    }

    // MARK: Focus

    private mutating func clearFocusCounts() {
        lowSince = nil
        highSince = nil
        goodCount = 0
        readingCount = 0
    }

    /// One reading of a focus pause. It ends once the picture has been sharp and still for
    /// `resumeSeconds`, allowing for the odd bad reading (`resumeGoodShare`). True when it ended.
    private mutating func judgeResume(good: Bool, _ now: Double) -> Bool {
        if good, highSince == nil {
            highSince = now
            goodCount = 0
            readingCount = 0
        }
        guard let since = highSince else { return false }
        readingCount += 1
        if good { goodCount += 1 }
        guard Double(goodCount) >= thresholds.resumeGoodShare * Double(readingCount) else {
            highSince = nil
            return false
        }
        return good && now - since >= thresholds.resumeSeconds - 1e-9
    }

    /// The pause's sharpness and its peak: medians of still readings; the peak only of readings
    /// with detail, within the window. A moving reading is smeared and says nothing.
    private mutating func updateSharpnessPeak(
        _ sharpness: Double?, hasDetail: Bool, isStill: Bool, _ now: Double
    ) {
        guard state == .pausedFocus, isStill, let sharpness else { return }
        recentSharpness = (recentSharpness + [(now, sharpness)]).suffix(thresholds.peakSmoothing)
        if hasDetail, recentSharpness.count == thresholds.peakSmoothing,
            let value = Self.median(recentSharpness.map(\.value))
        {
            sharpnessPeaks.append((now, value))
        }
    }

    private mutating func updateFocus(
        _ index: Double?, _ sharpness: Double?, _ viewClass: ViewClass, _ tracking: TrackingState,
        _ isStill: Bool, _ now: Double
    ) {
        focusLow = false
        isSharp = false
        // The index is read a few times a second: between readings the latest one stands, but
        // none older than the gap.
        if let last = lastIndex, now - last.seconds > thresholds.focusReadingGapSeconds {
            lastIndex = nil
        }
        // On every reading, so a gap without sharpness ages them too.
        sharpnessPeaks.removeAll { now - $0.seconds > thresholds.peakWindowSeconds }
        recentSharpness.removeAll { now - $0.seconds > thresholds.smoothingSeconds }
        let hasDetail = tracking == .tracking && (viewClass == .sample || viewClass == .thin)
        // Dark is neither: it ends a stretch without starting one.
        if tracking == .paused || viewClass == .blank || viewClass == .blurry {
            updateSharpnessPeak(sharpness, hasDetail: false, isStill: isStill, now)
            updateStretch(sharpness, isStill, now)
            return
        }
        stretch = nil
        stillOnset = false
        onsetSince = nil
        guard hasDetail else {
            missReading(now)
            return
        }
        detailHistory.append((now, isStill, sharpness))
        detailHistory.removeAll { now - $0.seconds > thresholds.stillOnsetLookbackSeconds }
        updateReference(sharpness)
        if state == .pausedFocus {
            // Sharp: against the baseline (or the run's own sharpness before the pause), and
            // about as sharp as this view has been. Without a baseline, detail is enough.
            if let index { lastIndex = (now, index) }
            updateSharpnessPeak(sharpness, hasDetail: true, isStill: isStill, now)
            let baseline = focusBaseline ?? 0
            let share = lastIndex.map { baseline > 0 ? $0.value / baseline : 1 }
            let indexBack =
                baseline <= 0 || (share ?? 0) >= thresholds.resumeAtShareOfBaseline
            let sharpBack = sharpnessShare.map { $0 >= thresholds.sharpnessResumeShare } ?? false
            isSharp = (indexBack || sharpBack) && isNearSharpnessPeak
            let sharpnessLow = sharpnessShare.map { $0 < thresholds.sharpnessPauseShare } ?? true
            focusLow =
                isStill && baseline > 0 && sharpnessLow
                && (share ?? 1) < thresholds.pauseBelowShareOfBaseline
            if isStill, let index {
                latestIndex = index
                if startIndex == nil { startIndex = index }
                if let began = pauseStartedAt, now - began >= thresholds.peakIgnoreSeconds {
                    peakIndex = max(peakIndex ?? index, index)
                }
            }
            if judgeResume(good: isSharp && isStill, now) {
                resumeNote = String(
                    format: "index=%.3f peak=%.3f share=%.2f", lastIndex?.value ?? -1,
                    peakIndex ?? -1, share ?? 1)
                state = .ok
                endFocusPause()
                clearFocusCounts()
            }
            return
        }
        guard isStill else {
            clearFocusCounts()
            return
        }
        if let index { latestIndex = index }
        let baseline = focusBaseline ?? 0
        guard baseline > 0 else {
            if let index { collectBaseline(index, now) }
            return
        }
        // Not measured on this frame (the caller reads it a few times a second): the counts
        // run on by time, neither added to nor cleared.
        guard let index else { return }
        if let last = lastFocusReadingAt, now - last > thresholds.focusReadingGapSeconds {
            clearFocusCounts()
        }
        lastFocusReadingAt = now
        // Both signals must say blurry. Before the reference exists the second is not checked.
        let sharpnessLow = sharpnessShare.map { $0 < thresholds.sharpnessPauseShare } ?? true
        focusLow = index / baseline < thresholds.pauseBelowShareOfBaseline && sharpnessLow
        lowSince = focusLow ? (lowSince ?? now) : nil
        if let lowSince, now - lowSince >= thresholds.pauseSeconds - 1e-9 {
            state = .pausedFocus
            beginFocusPause(now)
            pauseCause = "index_and_sharpness"
            clearFocusCounts()
        }
    }

    /// A reading that says nothing about focus: it ends a low count; in a focus pause it counts
    /// as not sharp.
    private mutating func missReading(_ now: Double) {
        guard state == .pausedFocus else { return clearFocusCounts() }
        lowSince = nil
        _ = judgeResume(good: false, now)
    }

    /// A reading without detail: the first of a stretch fixes what it is judged against (the
    /// detail readings just before); every reading re-checks the drop, as the stretch's median
    /// changes. Held for `pauseSeconds` it pauses for focus.
    private mutating func updateStretch(_ sharpness: Double?, _ isStill: Bool, _ now: Double) {
        missReading(now)
        if stretch == nil {
            let before = detailHistory.filter {
                now - $0.seconds <= thresholds.stillOnsetLookbackSeconds
            }
            stretch = LowDetailStretch(
                beforeStill: before.last?.isStill == true,
                beforeMedian: Self.median(before.compactMap(\.sharpness)))
        }
        guard var current = stretch else { return }
        if let sharpness { current.sharpness.append(sharpness) }
        stretch = current
        if let before = current.beforeMedian, let during = Self.median(current.sharpness) {
            stillOnset = current.beforeStill && during <= thresholds.detailDropShare * before
        } else {
            stillOnset = false
        }
        focusLow = stillOnset
        guard state == .ok, stillOnset else {
            onsetSince = nil
            return
        }
        onsetSince = onsetSince ?? now
        if let onsetSince, now - onsetSince >= thresholds.pauseSeconds - 1e-9 {
            state = .pausedFocus
            beginFocusPause(now)
            pauseCause = "detail_lost"
            self.onsetSince = nil
        }
    }

    /// Adds an eligible reading to the sharpness reference while the monitor is OK, and works out
    /// the latest share of it. The reference does not include the reading it is compared with.
    private mutating func updateReference(_ sharpness: Double?) {
        let span = (sharpnessHistory.last?.seconds ?? 0) - (sharpnessHistory.first?.seconds ?? 0)
        sharpnessReference =
            span >= thresholds.referenceMinimumSeconds - 1e-9
            ? Self.median(sharpnessHistory.map(\.value)) : nil
        if let reference = sharpnessReference, reference > 0, let sharpness {
            sharpnessShare = sharpness / reference
        } else {
            sharpnessShare = nil
        }
        guard state == .ok, let sharpness else { return }
        sharpnessHistory.append((referenceClock, sharpness))
        sharpnessHistory.removeAll { referenceClock - $0.seconds > thresholds.referenceSeconds }
    }

    private static func median(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.sorted()[values.count / 2]
    }

    /// With no baseline from setup: the median of the first `baselineSeconds` of eligible
    /// readings. Nothing is judged until then.
    private mutating func collectBaseline(_ index: Double, _ now: Double) {
        baselineSamples.append((now, index))
        guard let first = baselineSamples.first,
            now - first.seconds >= thresholds.baselineSeconds - 1e-9
        else { return }
        let sorted = baselineSamples.map(\.value).sorted()
        focusBaseline = sorted[sorted.count / 2]
        baselineSamples = []
    }
}

extension FrameAnalyzer {
    /// The focus index of `box`: the Laplacian variance sampled every 2nd pixel over the one
    /// sampled every 6th. Defocus takes away fine detail first, so the ratio falls with focus
    /// whatever the amount of sample. nil when the box cannot be measured.
    static func focusIndex(of pixelBuffer: CVPixelBuffer, in box: CGRect) -> Double? {
        guard let fine = stats(of: pixelBuffer, in: box, step: 2)?.sharpness,
            let coarse = stats(of: pixelBuffer, in: box, step: 6)?.sharpness, coarse > 1e-9
        else { return nil }
        return fine / coarse
    }
}

extension RunMonitor {
    /// Every condition for ending a pause for focus that is not met right now, as short names;
    /// empty when the monitor is not paused for focus (nothing is held back). Pure: it only
    /// restates the rules above and changes none of them. `index` is the latest focus index
    /// (nil when too old), `isSharp` the monitor's own verdict on this frame.
    static func whyNotResumed(
        state: RunMonitorState, index: Double?, baseline: Double?, sharpnessShare: Double?,
        isSharp: Bool, viewClass: ViewClass, tracking: TrackingState, isStill: Bool,
        thresholds t: RunMonitorThresholds = RunMonitorThresholds()
    ) -> [String] {
        guard state == .pausedFocus else { return [] }
        var reasons: [String] = []
        let viewFine = viewClass == .sample || viewClass == .thin
        let trackingFine = tracking == .tracking
        if !viewFine { reasons.append("view_class") }
        if !trackingFine { reasons.append("not_tracking") }
        let base = baseline ?? 0
        let indexBack =
            base <= 0 || (index.map { $0 / base >= t.resumeAtShareOfBaseline } ?? false)
        let sharpBack = sharpnessShare.map { $0 >= t.sharpnessResumeShare } ?? false
        if !(indexBack || sharpBack) {
            reasons.append(index == nil ? "no_index" : "index_below_resume")
            reasons.append("sharpness_below_share")
        } else if viewFine, trackingFine, !isSharp {
            reasons.append("not_near_peak")
        }
        if !isStill { reasons.append("moving") }
        if reasons.isEmpty { reasons.append("not_long_enough") }
        return reasons
    }
}
