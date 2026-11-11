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
    /// The odometer position in frames (position / short side).
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
    /// Distance from the marked start in frames; nil when no start is marked.
    var offStartFrames: Double?
    /// Where movement was registered: "auto-learned", "auto-untrusted", "auto-learning",
    /// "centre-square" or "whole-frame".
    var fieldRegion = ""
    /// Time spent analyzing this frame, in milliseconds.
    var analysisMilliseconds = 0.0
    /// Analyzed frames per second over the last second.
    var analyzedFps = 0.0
    /// The share of the frame that is open field; nil when no mask was learned.
    var fieldOpenShare: Double?
}

enum MovementLog {
    static let header = [
        "seconds", "brightness", "sharpness", "contrast",
        "shake_x_px", "shake_y_px", "anchor_x_px", "anchor_y_px",
        "position_x_px", "position_y_px", "position_x_frames", "position_y_frames",
        "hops", "gaps", "is_lost", "event", "hop_agreement",
        "label", "mark", "mark_mm", "frame_width", "frame_height",
        "test", "note", "speed_fraction", "status", "hop_progress", "still_seconds",
        "off_start_frames", "field_region", "analysis_ms", "analyzed_fps",
        "field_open_share",
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
            number(row.offStartFrames, 3), row.fieldRegion,
            number(row.analysisMilliseconds, 1), number(row.analyzedFps, 1),
            number(row.fieldOpenShare, 3),
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
