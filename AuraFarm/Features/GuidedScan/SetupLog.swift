import CoreGraphics
import Foundation

/// What the tracker saw on a frame of the field or stage step, for the log; nil while it
/// does not run.
struct SetupTrackerSample: Equatable {
    var tracking: TrackingState
    /// The guide's screen-field position the stage step measures from.
    var position: CGPoint
    var boxSharpness: Double
    var viewClass: ViewClass
    var stillSeconds: Double
    var featureCells = 0
}

/// One analyzed frame of the setup (align or focus): what the checks said. Kept in memory
/// for the "Export setup log" button, so the placeholder thresholds can be calibrated.
struct SetupLogRow: Equatable {
    /// Since the first setup frame.
    var seconds: Double
    var step: LabSetupStep
    var alignment: AlignmentReading
    var focus: FocusReading?
    /// The two-sided dial, once it shows.
    var focusDial: FocusDialReading?
    /// The stage step's progress and, once known, the measured axes.
    var stage: StageAxesProgress?
    var stageAxes: StageAxes?
    var tracker: SetupTrackerSample?
    /// The focus tiles' reading on this frame (the focus step), for the log only.
    var focusTiles: FocusTilesReading?
    /// The highest detail at this spot (since the focus guide last reset), once there is one.
    var focusDetailBest: Double?
    /// What happened to the focus on this row: "new_spot", or "focus_accept_<who>_<where>".
    var focusEvent = ""
}

enum SetupLog {
    /// The least that is kept, in seconds: older rows are dropped.
    static let keepSeconds = 120.0

    static let header = [
        "seconds", "step", "found", "circle_x", "circle_y", "circle_r", "clipped_sides",
        "roundness", "evenness", "darkest_sector", "brightest_sector", "saturated_share",
        "glare_ratio", "score", "problems", "focus_state", "focus_current", "focus_peak",
        "focus_level", "stage_step", "stage_travel_fields", "stage_tilt_deg", "stage_skew_deg",
        "tracking", "position_x_fields", "position_y_fields", "box_sharpness", "view_class",
        "still_seconds", "feature_cells", "focus_dial_offset", "focus_dial_side",
        "focus_top", "focus_top_ratio", "focus_noise", "focus_tiles_used", "focus_tiles_active",
        "focus_detail", "focus_detail_best", "focus_tile_fine", "focus_tile_coarse", "focus_event",
    ]

    static func csv(_ rows: [SetupLogRow]) -> String {
        CSV.document(header: header, rows: rows.map(fields))
    }

    private static func fields(_ row: SetupLogRow) -> [String] {
        let reading = row.alignment
        let sides = FrameSide.allCases.filter { reading.clippedSides.contains($0) }
            .map { "\($0)" }.joined(separator: " ")
        return [
            number(row.seconds, 2), row.step.csvName, reading.found ? "1" : "0",
            number(reading.circle.map { Double($0.centre.x) }, 1),
            number(reading.circle.map { Double($0.centre.y) }, 1),
            number(reading.circle?.radius, 1), sides, number(reading.roundness, 3),
            number(reading.evenness, 3), reading.darkestSector.map(String.init) ?? "",
            reading.brightestSector.map(String.init) ?? "",
            number(reading.saturatedShare, 4), number(reading.glareRatio, 3),
            number(reading.score, 1), reading.problems.map(\.csvName).joined(separator: " "),
            row.focus?.state.csvName ?? "", number(row.focus?.current, 1),
            number(row.focus?.peak, 1), number(row.focus?.level, 3),
            row.stage?.step.csvName ?? "", number(row.stage?.travelFields, 2),
            number(row.stageAxes?.tiltDegrees, 2), number(row.stageAxes?.skewDegrees, 2),
            row.tracker.map { Self.trackingName($0.tracking) } ?? "",
            number(row.tracker.map { Double($0.position.x) }, 3),
            number(row.tracker.map { Double($0.position.y) }, 3),
            number(row.tracker?.boxSharpness, 1), row.tracker?.viewClass.rawValue ?? "",
            number(row.tracker?.stillSeconds, 2),
            row.tracker.map { String($0.featureCells) } ?? "",
            number(row.focusDial?.offset, 3), row.focusDial?.csvSide ?? "",
            significant(row.focusTiles?.top), significant(row.focusTiles?.topRatio),
            significant(row.focusTiles?.noise), row.focusTiles.map { String($0.used) } ?? "",
            row.focusTiles.map { String($0.active) } ?? "",
            significant(row.focusTiles?.detail), significant(row.focusDetailBest),
            row.focusTiles.map { FocusTilesReading.text($0.tileFine) } ?? "",
            row.focusTiles.map { FocusTilesReading.text($0.tileCoarse) } ?? "", row.focusEvent,
        ]
    }

    static func trackingName(_ state: TrackingState) -> String {
        switch state {
        case .tracking: "tracking"
        case .paused: "paused"
        case .matching: "matching"
        case .lost: "lost"
        }
    }

    /// Four significant digits, always with a dot; empty for nil.
    private static func significant(_ value: Double?) -> String {
        value.map { String(format: "%.4g", $0) } ?? ""
    }

    /// Fixed decimals, always with a dot; empty for nil.
    private static func number(_ value: Double?, _ places: Int) -> String {
        guard let value else { return "" }
        return value.formatted(
            .number.precision(.fractionLength(places)).grouping(.never).locale(
                Locale(identifier: "en_US_POSIX")))
    }
}
