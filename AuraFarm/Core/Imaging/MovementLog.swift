import Foundation

/// One analyzed frame of the slide movement lab, as a CSV row.
struct MovementLogRow: Equatable {
    /// Since the log started.
    var seconds: Double
    var brightness: Double
    var sharpness: Double
    var contrast: Double
    /// `ShakeEstimator.lastShift`: frame to frame, px.
    var shakeX: Double?
    var shakeY: Double?
    /// The live offset from the anchor, px.
    var anchorX: Double?
    var anchorY: Double?
    /// The odometer position, px.
    var positionX: Double
    var positionY: Double
    /// The odometer position in frames (position / the frame's short side).
    var positionXFrames: Double
    var positionYFrames: Double
    var hops: Int
    var gaps: Int
    var isLost: Bool
    /// "", "hop", "lost" or "regained".
    var event: String
    /// `PanoramaStitcher.agreement` at a hop, if it was measured.
    var hopAgreement: Double?
    /// "sample", "blank", "blurry" or "".
    var label: String
    /// "", "start" or "end".
    var mark: String
    /// Typed by the team at "end", from the stage's vernier scale.
    var markMillimetres: Double?
    var frameWidth: Int
    var frameHeight: Int
    /// `SlideLabTest.fileSlug`.
    var test = ""
    /// Free text typed by the team for this log.
    var note = ""
    /// Frame-to-frame movement as a share of the short side, averaged.
    var speedFraction = 0.0
    /// "starting", "tracking", "too_fast" or "lost".
    var status = ""
    /// 0...1 towards the next hop.
    var hopProgress = 0.0
    var stillSeconds = 0.0
    /// Distance from the marked start in fields (box sides); nil when no start is marked.
    var offStartFields: Double?
    /// Where movement was registered: "auto-learned", "auto-untrusted", "auto-learning",
    /// "bright-region-learned" (and "-untrusted", "-learning"), "centre-square" or
    /// "whole-frame".
    var fieldRegion = ""
    /// Time spent analyzing this frame, in milliseconds.
    var analysisMilliseconds = 0.0
    /// Analyzed frames per second over the last second.
    var analyzedFps = 0.0
    /// The share of the frame that is open field; nil when no mask was learned.
    var fieldOpenShare: Double?
    /// The side of the registration box in px; the frame's short side with no box.
    var boxSidePx = 0.0
    /// The odometer position in fields (position / box side).
    var positionXFields = 0.0
    var positionYFields = 0.0
    /// The hop distance in use, px.
    var hopLimitPx = 0.0
    /// Brightness, sharpness and contrast measured inside the registration box only (the
    /// whole frame when there is no box). The three columns before these are whole-frame.
    var boxBrightness = 0.0
    var boxSharpness = 0.0
    var boxContrast = 0.0
    /// "measured", "predicted" or "missing": see `ReadingVerdict`.
    var reading = ""
    /// Readings in a row replaced by a prediction.
    var predictedStreak = 0
    /// True while the box held too little detail to follow (`DetailCheck`).
    var noDetail = false
    /// Times the view went over nothing to track.
    var blindStretches = 0
    /// The picture check against the Mark start picture: where the start picture sits against
    /// this frame (px), the true distance from the start and the tracker's error, in fields.
    /// nil when not available.
    var startMatchX: Double?
    var startMatchY: Double?
    var trueOffStartFields: Double?
    var trackerErrorFields: Double?
    /// Detail returns recovered by matching the held picture, and those that were not.
    var blankReturnsMatched = 0
    var blankReturnsUnmatched = 0
    /// "matched" or "unmatched" on the frame where a return was decided, else "".
    var blankReturn = ""
    /// The guide dry run; empty when it is off. `viewClass` is what the box looks like.
    var viewClass = ""
    var guideState = ""
    var guideInstruction = ""
    var guideTargetDx: Double?
    var guideTargetDy: Double?
    var guideCaptures: Int?
    /// The mapping the guide's screen axes are nearest to; empty when the guide is off.
    var guideAxesMapping = ""
    /// The sharpness of each half of the box, in frame axes; nil when there was no box.
    var boxSharpLeft: Double?
    var boxSharpRight: Double?
    var boxSharpTop: Double?
    var boxSharpBottom: Double?
    /// Each half's sharpness over the same content's in the anchor frame; see
    /// `SlideTrackerReading.halfFocusRatio`.
    var focusLeft: Double?
    var focusRight: Double?
    var focusTop: Double?
    var focusBottom: Double?
    /// What the guide's edge conditions made of this frame; empty when the guide is off. See
    /// `EdgeDiagnostics`.
    var edgeCandidate = ""
    var edgeVerdict = ""
    var edgeReason = ""
    /// The sharpness of the two halves across the guide's heading that the route used.
    var boxSharpSideA: Double?
    var boxSharpSideB: Double?
    /// The run monitor: "ok", "paused_alignment" or "paused_focus"; the focus index (box
    /// Laplacian variance at step 2 over step 6) and its baseline; and how far the eyepiece
    /// circle is from the confirmed one (centre shift as a share of the radius, and radius
    /// change). Empty before setup is done.
    var monitorState = ""
    var focusIndex: Double?
    var focusBaseline: Double?
    var circleShiftR: Double?
    var circleRadiusChange: Double?
    /// The monitor held a capture off because focus was clearly low.
    var focusLow = false
    /// Detail was lost while the slide was still: focus or a bump, not an edge.
    var focusStillOnset = false
    /// The edge-line detector's result on frames it ran on; nil elsewhere. Logged only.
    var edgeLine: EdgeLine?
    /// Distinct features in the box (see `FeatureCells`) and whether the tracker followed this
    /// frame only because of the sparse rule.
    var featureCells = 0
    var featureQuarters = 0
    var sparseTracking = false
    /// While paused for focus with a baseline: the dial's offset (-1 not far enough, +1 too far)
    /// and side ("approaching", "past", "unknown" or "wrong_way").
    var focusDialOffset: Double?
    var focusDialSide = ""
    /// The file name of the frame saved on this row (lab only), else empty.
    var snapshot = ""
    /// The four quarters in heading terms (relative to the low side half across the heading)
    /// and the corner rule's box share; empty when not known.
    var quadAheadAway: Double?
    var quadAheadToward: Double?
    var quadBehindAway: Double?
    var quadBehindToward: Double?
    var cornerBoxShare: Double?
    /// The sum of the frame-to-frame shifts since the anchor, and how far the anchor reading
    /// was from it (px); empty when not available.
    var chainX: Double?
    var chainY: Double?
    var anchorChainGap: Double?
    /// Frames dropped as ghosts so far (a running count) and the times a run of them gave up.
    var ghostFrames = 0
    var ghostFallbacks = 0
    /// Full-cover-slip mode: how far the edge line has got ("none", "ahead", "attached",
    /// "confirmed"), how many of the last moving readings were attached to the slide, and the
    /// edge mode ("line" or "legacy"); empty before the guide runs.
    var lineState = ""
    var lineAttachedCount = 0
    var edgeMode = ""
    /// Frames skipped as near empty so far (a running count).
    var sparseSkips = 0
    /// "yes", "no" or "mark" on the row of a tap on an edge button, "auto" when the rule confirmed
    /// an edge by itself, else empty.
    var edgeFeedback = ""
    /// Brief-touch mode: "brief_touch" or "hold_still", where the view is against the spot's window
    /// ("in", "ahead", "behind" or empty), how long it has been inside, and the running count of
    /// spots passed without a touch; the coverage step in fields. Empty without the guide.
    var spotMode = ""
    var spotWindow = ""
    var touchSeconds: Double?
    var missedSpots: Int?
    var coverageStep: Double?
    /// Live counting: whether it is on, whether the detector ran on this frame (else why not), how
    /// long it took, and what it found and counted. Totals are running.
    var countingActive = false
    var detRan = false
    var detSkipReason = ""
    var detMilliseconds: Double?
    var detFound: Int?
    var detOutside: Int?
    var detNewTally: Int?
    var detNewMap: Int?
    var detRepeatMap: Int?
    var countTallyTotal: Int?
    var countMapTotal: Int?
    /// More about an event row: an organism counted (label, id, slide position, column) or the
    /// run's summary.
    var eventDetail = ""
    /// The detector model counting ("v1" or "v2") and the boxes the guards dropped on this frame
    /// as the eyepiece disc and as too big.
    var detectorModel = ""
    var detDropDisc: Int?
    var detDropBig: Int?
    /// The hardware the counting model runs on ("ne" or "gpu"), seconds since the previous analysed
    /// frame, and what the camera and the phone were doing: the camera's measured rate, the
    /// exposure and the ISO, the thermal state and the battery level (0 to 1).
    var detUnits = ""
    var frameDt: Double?
    var cameraFps: Double?
    var exposureMs: Double?
    var iso: Double?
    var thermalState = ""
    var batteryLevel: Double?
    /// The focus pause's second signal: the rolling box-sharpness reference, the latest sharpness
    /// over it, and why the run is paused ("index_and_sharpness", "detail_lost", "alignment").
    var sharpnessRef: Double?
    var sharpnessShare: Double?
    var pauseCause = ""
    /// The detector's result arrives after its frame: when the frame it ran on was taken (run
    /// seconds), and where its time went: crop and render, the model alone, and decoding.
    var detFrameSeconds: Double?
    var detPreMs: Double?
    var detInferMs: Double?
    var detDecodeMs: Double?
    /// Which rule accepted the latest edge line ("strict" or "area"; empty without one), and the
    /// detail ahead over the detail behind that the area rule used.
    var lineAccept = ""
    var areaAheadShare: Double?
    /// The predicted edge's position along the leg at the column's x, and 1 on the readings where
    /// "Edge should be here. Confirm?" shows.
    var predictedEdgeAlong: Double?
    var expectedEdgeAsk = false
    /// Frames the camera output dropped as late so far (a running count).
    var cameraDrops: Int?
}

enum MovementLog {
    static let header = [
        "seconds", "brightness", "sharpness", "contrast",
        "shake_x_px", "shake_y_px", "anchor_x_px", "anchor_y_px",
        "position_x_px", "position_y_px", "position_x_frames", "position_y_frames",
        "hops", "gaps", "is_lost", "event", "hop_agreement",
        "label", "mark", "mark_mm", "frame_width", "frame_height",
        "test", "note", "speed_fraction", "status", "hop_progress", "still_seconds",
        "off_start_fields", "field_region", "analysis_ms", "analyzed_fps",
        "field_open_share", "box_side_px", "position_x_fields", "position_y_fields",
        "hop_limit_px", "box_brightness", "box_sharpness", "box_contrast",
        "reading", "predicted_streak", "no_detail", "blind_stretches",
        "start_match_x_px", "start_match_y_px", "true_off_start_fields", "tracker_error_fields",
        "blank_returns_matched", "blank_returns_unmatched", "blank_return",
        "view_class", "guide_state", "guide_instruction", "guide_target_dx", "guide_target_dy",
        "guide_captures", "guide_axes_mapping",
        "box_sharp_left", "box_sharp_right", "box_sharp_top", "box_sharp_bottom",
        "focus_left", "focus_right", "focus_top", "focus_bottom",
        "edge_candidate", "edge_verdict", "edge_reason", "box_sharp_side_a", "box_sharp_side_b",
        "monitor_state", "focus_index", "focus_baseline", "circle_shift_r", "circle_radius_change",
        "focus_low", "focus_still_onset",
        "edge_line_strength", "edge_line_coverage", "edge_line_angle_deg",
        "edge_line_offset_fields", "edge_line_sign", "edge_line_slide_residual",
        "edge_line_candidate", "feature_cells", "feature_quarters", "sparse_tracking",
        "focus_dial_offset", "focus_dial_side", "edge_line_longest_run", "snapshot",
        "quad_ahead_away", "quad_ahead_toward", "quad_behind_away", "quad_behind_toward",
        "corner_box_share", "chain_x_px", "chain_y_px", "anchor_chain_gap_px",
        "ghost_frames", "ghost_fallbacks", "line_state", "line_attached_count", "edge_mode",
        "sparse_skips", "line_before_energy", "line_beyond_energy",
        "edge_feedback", "line_attach_source",
        "spot_mode", "spot_window", "touch_seconds", "missed_spots", "coverage_step",
        "counting_active", "det_ran", "det_skip_reason", "det_ms", "det_found", "det_outside",
        "det_new_tally", "det_new_map", "det_repeat_map", "count_tally_total", "count_map_total",
        "event_detail", "detector_model", "det_drop_disc", "det_drop_big",
        "det_units", "frame_dt", "camera_fps", "exposure_ms", "iso", "thermal_state", "battery_level",
        "sharpness_ref", "sharpness_share", "pause_cause", "det_frame_seconds", "det_pre_ms",
        "det_infer_ms", "det_decode_ms",
        "line_accept", "area_ahead_share", "predicted_edge_along", "expected_edge_ask",
        "camera_drops",
    ]

    static func csv(_ rows: [MovementLogRow]) -> String {
        CSV.document(header: header, rows: rows.map(fields))
    }

    private static func fields(_ row: MovementLogRow) -> [String] {
        [
            number(row.seconds, 2), number(row.brightness, 3), number(row.sharpness, 3),
            number(row.contrast, 3),
            number(row.shakeX, 2), number(row.shakeY, 2),
            number(row.anchorX, 2), number(row.anchorY, 2),
            number(row.positionX, 2), number(row.positionY, 2),
            number(row.positionXFrames, 3), number(row.positionYFrames, 3),
            String(row.hops), String(row.gaps), row.isLost ? "1" : "0",
            row.event, number(row.hopAgreement, 3),
            row.label, row.mark, number(row.markMillimetres, 2),
            String(row.frameWidth), String(row.frameHeight),
            row.test, row.note, number(row.speedFraction, 3), row.status,
            number(row.hopProgress, 2), number(row.stillSeconds, 2),
            number(row.offStartFields, 3), row.fieldRegion,
            number(row.analysisMilliseconds, 1), number(row.analyzedFps, 1),
            number(row.fieldOpenShare, 3), number(row.boxSidePx, 1),
            number(row.positionXFields, 3), number(row.positionYFields, 3),
            number(row.hopLimitPx, 1),
            number(row.boxBrightness, 3), number(row.boxSharpness, 3),
            number(row.boxContrast, 3), row.reading, String(row.predictedStreak),
            row.noDetail ? "1" : "0", String(row.blindStretches),
            number(row.startMatchX, 2), number(row.startMatchY, 2),
            number(row.trueOffStartFields, 3), number(row.trackerErrorFields, 3),
            String(row.blankReturnsMatched), String(row.blankReturnsUnmatched), row.blankReturn,
            row.viewClass, row.guideState, row.guideInstruction,
            number(row.guideTargetDx, 2), number(row.guideTargetDy, 2),
            row.guideCaptures.map(String.init) ?? "", row.guideAxesMapping,
            number(row.boxSharpLeft, 3), number(row.boxSharpRight, 3),
            number(row.boxSharpTop, 3), number(row.boxSharpBottom, 3),
            number(row.focusLeft, 3), number(row.focusRight, 3), number(row.focusTop, 3),
            number(row.focusBottom, 3),
            row.edgeCandidate, row.edgeVerdict, row.edgeReason,
            number(row.boxSharpSideA, 3), number(row.boxSharpSideB, 3),
            row.monitorState, number(row.focusIndex, 3), number(row.focusBaseline, 3),
            number(row.circleShiftR, 3), number(row.circleRadiusChange, 3),
            row.focusLow ? "1" : "0", row.focusStillOnset ? "1" : "0",
            number(row.edgeLine?.strength, 2), number(row.edgeLine?.coverage, 3),
            number(row.edgeLine?.angleDegrees, 1), number(row.edgeLine?.offsetFields, 3),
            row.edgeLine.map { String($0.sign) } ?? "",
            number(row.edgeLine?.slideResidualFields, 3),
            row.edgeLine.map { $0.isCandidate ? "1" : "0" } ?? "",
            String(row.featureCells), String(row.featureQuarters), row.sparseTracking ? "1" : "0",
            number(row.focusDialOffset, 3), row.focusDialSide,
            row.edgeLine.map { String($0.longestRun) } ?? "", row.snapshot,
            number(row.quadAheadAway, 1), number(row.quadAheadToward, 1),
            number(row.quadBehindAway, 1), number(row.quadBehindToward, 1),
            number(row.cornerBoxShare, 3),
            number(row.chainX, 2), number(row.chainY, 2), number(row.anchorChainGap, 2),
            String(row.ghostFrames), String(row.ghostFallbacks), row.lineState,
            row.lineState.isEmpty ? "" : String(row.lineAttachedCount), row.edgeMode,
            String(row.sparseSkips), number(row.edgeLine?.beforeEnergy, 2),
            number(row.edgeLine?.beyondEnergy, 2), row.edgeFeedback,
            row.edgeLine?.attachSource ?? "",
            row.spotMode, row.spotWindow, number(row.touchSeconds, 2),
            row.missedSpots.map(String.init) ?? "", number(row.coverageStep, 1),
            row.spotMode.isEmpty ? "" : (row.countingActive ? "1" : "0"),
            row.countingActive ? (row.detRan ? "1" : "0") : "", row.detSkipReason,
            number(row.detMilliseconds, 1), row.detFound.map(String.init) ?? "",
            row.detOutside.map(String.init) ?? "", row.detNewTally.map(String.init) ?? "",
            row.detNewMap.map(String.init) ?? "", row.detRepeatMap.map(String.init) ?? "",
            row.countTallyTotal.map(String.init) ?? "", row.countMapTotal.map(String.init) ?? "",
            row.eventDetail, row.detectorModel, row.detDropDisc.map(String.init) ?? "",
            row.detDropBig.map(String.init) ?? "",
            row.detUnits, number(row.frameDt, 3), number(row.cameraFps, 1),
            number(row.exposureMs, 2), number(row.iso, 0), row.thermalState,
            number(row.batteryLevel, 2),
            number(row.sharpnessRef, 1), number(row.sharpnessShare, 2), row.pauseCause,
            number(row.detFrameSeconds, 3), number(row.detPreMs, 1), number(row.detInferMs, 1),
            number(row.detDecodeMs, 1),
            row.lineAccept, number(row.areaAheadShare, 3), number(row.predictedEdgeAlong, 3),
            row.lineState.isEmpty ? "" : (row.expectedEdgeAsk ? "1" : "0"),
            row.cameraDrops.map(String.init) ?? "",
        ]
    }

    /// Fixed decimals, always with a dot; empty for nil.
    private static func number(_ value: Double?, _ places: Int) -> String {
        guard let value else { return "" }
        return value.formatted(
            .number.precision(.fractionLength(places)).grouping(.never).locale(
                Locale(identifier: "en_US_POSIX")))
    }
}
