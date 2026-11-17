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
    var lostCentreShiftShareOfRadius: Double = 0.12
    /// The circle's radius changed by this share.
    var lostRadiusChange: Double = 0.10
    var lostMinRoundness: Double = 0.75
    /// Lost (a clipped circle, no circle, or the limits above) for this long without a break.
    var lostSeconds: Double = 2.0
    /// Back: within these of the confirmed circle, for `backSeconds`.
    var backCentreShiftShareOfRadius: Double = 0.06
    var backRadiusChange: Double = 0.05
    var backSeconds: Double = 1.0

    // Focus. The focus index is the box's Laplacian variance at step 2 over step 6: fine detail
    // fades first when defocused, so the ratio falls whatever the amount of sample.
    var pauseBelowShareOfBaseline: Double = 0.6
    var pauseSeconds: Double = 2.5
    var resumeAtShareOfBaseline: Double = 0.8
    var resumeSeconds: Double = 1.0
    /// With no baseline from setup: the median of this many seconds of eligible readings.
    var baselineSeconds: Double = 3.0
    /// A real defocus: detail lost while STILL. The readings with detail this far back give the
    /// "before" (matches `GuidedSweepThresholds.checkEdgeLookbackSeconds`). PLACEHOLDER.
    var stillOnsetLookbackSeconds: Double = 0.5
    /// The low-detail stretch's median box sharpness must be at or under this share of the
    /// lookback's. PLACEHOLDER: a real defocus drops far more; a thin patch flickering around
    /// the detail limit (Test 4 soil: 17 to 150 against 200 to 400) does not count.
    var detailDropShare: Double = 0.5
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
        if let alignment { updateAlignment(alignment, confirmedCircle, seconds) }
        guard state != .pausedAlignment else {
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
                goodSince = nil
                clearFocusCounts()
            }
        }
    }

    // MARK: Focus

    private mutating func clearFocusCounts() {
        lowSince = nil
        highSince = nil
    }

    private mutating func updateFocus(
        _ index: Double?, _ sharpness: Double?, _ viewClass: ViewClass, _ tracking: TrackingState,
        _ isStill: Bool, _ now: Double
    ) {
        focusLow = false
        let hasDetail = tracking == .tracking && (viewClass == .sample || viewClass == .thin)
        // Dark is neither: it ends a stretch without starting one.
        if tracking == .paused || viewClass == .blank || viewClass == .blurry {
            updateStretch(sharpness, isStill, now)
            return
        }
        stretch = nil
        stillOnset = false
        onsetSince = nil
        guard hasDetail else {
            clearFocusCounts()
            return
        }
        detailHistory.append((now, isStill, sharpness))
        detailHistory.removeAll { now - $0.seconds > thresholds.stillOnsetLookbackSeconds }
        guard isStill else {
            clearFocusCounts()
            return
        }
        let baseline = focusBaseline ?? 0
        var share = 1.0
        if baseline > 0 {
            guard let index else {
                clearFocusCounts()
                return
            }
            share = index / baseline
        } else if state != .pausedFocus {
            if let index { collectBaseline(index, now) }
            return
        }
        // Without a baseline a pause for focus resumes on detail plus stillness alone (share 1).
        focusLow = baseline > 0 && share < thresholds.pauseBelowShareOfBaseline
        switch state {
        case .ok:
            lowSince = focusLow ? (lowSince ?? now) : nil
            if let lowSince, now - lowSince >= thresholds.pauseSeconds - 1e-9 {
                state = .pausedFocus
                clearFocusCounts()
            }
        case .pausedFocus:
            highSince = share >= thresholds.resumeAtShareOfBaseline ? (highSince ?? now) : nil
            if let highSince, now - highSince >= thresholds.resumeSeconds - 1e-9 {
                state = .ok
                clearFocusCounts()
            }
        case .pausedAlignment:
            break
        }
    }

    /// A reading without detail: the first of a stretch fixes what it is judged against (the
    /// detail readings just before); every reading re-checks the drop, as the stretch's median
    /// changes. Held for `pauseSeconds` it pauses for focus.
    private mutating func updateStretch(_ sharpness: Double?, _ isStill: Bool, _ now: Double) {
        clearFocusCounts()
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
            self.onsetSince = nil
        }
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
