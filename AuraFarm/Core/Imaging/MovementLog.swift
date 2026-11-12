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
