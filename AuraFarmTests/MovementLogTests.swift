import XCTest

@testable import AuraFarm

final class MovementLogTests: XCTestCase {
    private func row(label: String = "", mark: String = "") -> MovementLogRow {
        MovementLogRow(
            seconds: 1.234, brightness: 120.12345, sharpness: 5.5, contrast: 30,
            shakeX: nil, shakeY: nil, anchorX: 3.456, anchorY: -2,
            positionX: 10, positionY: -20, positionXFrames: 0.0139, positionYFrames: -0.0278,
            hops: 2, gaps: 1, isLost: false, event: "", hopAgreement: nil,
            label: label, mark: mark, markMillimetres: nil, frameWidth: 1280, frameHeight: 720,
            test: "drift", note: "hand 10x", speedFraction: 0.0456, status: "too_fast",
            hopProgress: 0.5, stillSeconds: 1.234, offStartFields: nil, fieldRegion: "auto-learned",
            analysisMilliseconds: 41.66, analyzedFps: 9.84, fieldOpenShare: 0.6234, boxSidePx: 352.04,
            positionXFields: 0.0284, positionYFields: -0.0568, hopLimitPx: 88.01,
            boxBrightness: 63.4567, boxSharpness: 412.3456, boxContrast: 18.25, reading: "predicted",
            predictedStreak: 2, noDetail: true, blindStretches: 3, startMatchX: 41.234,
            startMatchY: -3.5, trueOffStartFields: 0.12, trackerErrorFields: 0.183,
            blankReturnsMatched: 2, blankReturnsUnmatched: 1, blankReturn: "matched",
            viewClass: "sample", guideState: "column 2 up", guideInstruction: "move",
            guideTargetDx: 0.5, guideTargetDy: -0.8, guideCaptures: 7,
            guideAxesMapping: "rotateLeft-mirrored", boxSharpLeft: 301.2346, boxSharpRight: 98.7654,
            boxSharpTop: 250, boxSharpBottom: 120.5, focusLeft: 0.9512, focusRight: 0.31,
            focusTop: 1.2, focusBottom: nil, edgeCandidate: "half_edge", edgeVerdict: "checking",
            edgeReason: "side_imbalance", boxSharpSideA: 40.5, boxSharpSideB: 400)
    }

    func testHeaderAndEveryRowHaveTheSameColumnCount() {
        let lines = MovementLog.csv([row(), row(mark: "end")]).split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        let columns = MovementLog.header.count
        for line in lines {
            XCTAssertEqual(line.split(separator: ",", omittingEmptySubsequences: false).count, columns)
        }
        XCTAssertTrue(lines[0].hasPrefix("seconds,brightness"))
    }

    func testNilFieldsAreEmptyAndNumbersAreFixed() {
        let line = MovementLog.csv([row()]).split(separator: "\n")[1]
        let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        let index = { MovementLog.header.firstIndex(of: $0)! }
        XCTAssertEqual(fields[index("seconds")], "1.23")
        XCTAssertEqual(fields[index("brightness")], "120.123")
        XCTAssertEqual(fields[index("shake_x_px")], "")
        XCTAssertEqual(fields[index("hop_agreement")], "")
        XCTAssertEqual(fields[index("mark_mm")], "")
        XCTAssertEqual(fields[index("anchor_x_px")], "3.46")
        XCTAssertEqual(fields[index("position_x_frames")], "0.014")
        XCTAssertEqual(fields[index("frame_width")], "1280")
        XCTAssertEqual(
            MovementLog.header.suffix(138).prefix(7),
            [
                "box_brightness", "box_sharpness", "box_contrast", "reading", "predicted_streak",
                "no_detail", "blind_stretches",
            ])
        XCTAssertEqual(
            MovementLog.header.suffix(131).prefix(27),
            [
                "start_match_x_px", "start_match_y_px", "true_off_start_fields",
                "tracker_error_fields", "blank_returns_matched", "blank_returns_unmatched",
                "blank_return", "view_class", "guide_state", "guide_instruction",
                "guide_target_dx", "guide_target_dy", "guide_captures", "guide_axes_mapping",
                "box_sharp_left", "box_sharp_right", "box_sharp_top", "box_sharp_bottom",
                "focus_left", "focus_right", "focus_top", "focus_bottom",
                "edge_candidate", "edge_verdict", "edge_reason", "box_sharp_side_a",
                "box_sharp_side_b",
            ])
        XCTAssertEqual(fields[index("start_match_x_px")], "41.23")
        XCTAssertEqual(fields[index("true_off_start_fields")], "0.120")
        XCTAssertEqual(fields[index("tracker_error_fields")], "0.183")
        XCTAssertEqual(fields[index("blank_returns_matched")], "2")
        XCTAssertEqual(fields[index("blank_returns_unmatched")], "1")
        XCTAssertEqual(fields[index("blank_return")], "matched")
        XCTAssertEqual(fields[index("view_class")], "sample")
        XCTAssertEqual(fields[index("guide_state")], "column 2 up")
        XCTAssertEqual(fields[index("guide_instruction")], "move")
        XCTAssertEqual(fields[index("guide_target_dx")], "0.50")
        XCTAssertEqual(fields[index("guide_captures")], "7")
        XCTAssertEqual(fields[index("guide_axes_mapping")], "rotateLeft-mirrored")
        XCTAssertEqual(fields[index("box_sharp_left")], "301.235")
        XCTAssertEqual(fields[index("box_sharp_bottom")], "120.500")
        XCTAssertEqual(fields[index("focus_left")], "0.951")
        XCTAssertEqual(fields[index("edge_candidate")], "half_edge")
        XCTAssertEqual(fields[index("edge_verdict")], "checking")
        XCTAssertEqual(fields[index("edge_reason")], "side_imbalance")
        XCTAssertEqual(fields[index("box_sharp_side_a")], "40.500")
        XCTAssertEqual(fields[index("box_sharp_side_b")], "400.000")
        XCTAssertEqual(fields[index("focus_top")], "1.200")
        XCTAssertEqual(fields[index("focus_bottom")], "", "a half with no ratio is empty")
        XCTAssertEqual(
            MovementLog.header.suffix(103).prefix(5),
            ["focus_index", "focus_baseline", "circle_shift_r", "circle_radius_change", "focus_low"],
            "the run monitor's columns are appended after every column")
        XCTAssertEqual(fields[index("monitor_state")], "")
        XCTAssertEqual(fields[index("focus_index")], "")
        XCTAssertEqual(fields[index("box_brightness")], "63.457")
        XCTAssertEqual(fields[index("box_sharpness")], "412.346")
        XCTAssertEqual(fields[index("box_contrast")], "18.250")
        XCTAssertEqual(fields[index("reading")], "predicted")
        XCTAssertEqual(fields[index("predicted_streak")], "2")
        XCTAssertEqual(fields[index("no_detail")], "1")
        XCTAssertEqual(fields[index("blind_stretches")], "3")
        XCTAssertEqual(fields[index("test")], "drift")
        XCTAssertEqual(fields[index("note")], "hand 10x")
        XCTAssertEqual(fields[index("speed_fraction")], "0.046")
        XCTAssertEqual(fields[index("status")], "too_fast")
        XCTAssertEqual(fields[index("still_seconds")], "1.23")
        XCTAssertEqual(fields[index("off_start_fields")], "")
        XCTAssertEqual(fields[index("field_region")], "auto-learned")
        XCTAssertEqual(fields[index("field_open_share")], "0.623")
        XCTAssertEqual(fields[index("analysis_ms")], "41.7")
        XCTAssertEqual(fields[index("analyzed_fps")], "9.8")
        XCTAssertEqual(fields[index("box_side_px")], "352.0")
        XCTAssertEqual(fields[index("position_x_fields")], "0.028")
        XCTAssertEqual(fields[index("position_y_fields")], "-0.057")
        XCTAssertEqual(fields[index("hop_limit_px")], "88.0")
    }

    func testAPendingMarkLandsInTheNextRowOnly() throws {
        var slot = MarkSlot()
        slot.place(PendingMark(name: "start", millimetres: nil))
        let first = try XCTUnwrap(slot.take())
        slot.place(PendingMark(name: "end", millimetres: 4.5))
        let second = try XCTUnwrap(slot.take())
        XCTAssertNil(slot.take(), "a mark is written once")
        let csv = MovementLog.csv([
            row(mark: first.name),
            {
                var end = row(mark: second.name)
                end.markMillimetres = second.millimetres
                return end
            }(),
            row(),
        ])
        let lines = csv.split(separator: "\n").map {
            $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        }
        let mark = try XCTUnwrap(MovementLog.header.firstIndex(of: "mark"))
        let mm = try XCTUnwrap(MovementLog.header.firstIndex(of: "mark_mm"))
        XCTAssertEqual(lines[1][mark], "start")
        XCTAssertEqual(lines[2][mark], "end")
        XCTAssertEqual(lines[2][mm], "4.50")
        XCTAssertEqual(lines[3][mark], "")
    }

    func testGuideAndPictureColumnsAreEmptyWhenOff() {
        var plain = row()
        plain.startMatchX = nil
        plain.startMatchY = nil
        plain.trueOffStartFields = nil
        plain.trackerErrorFields = nil
        plain.viewClass = ""
        plain.guideState = ""
        plain.guideInstruction = ""
        plain.guideTargetDx = nil
        plain.guideTargetDy = nil
        plain.guideCaptures = nil
        plain.guideAxesMapping = ""
        plain.boxSharpLeft = nil
        plain.boxSharpRight = nil
        plain.boxSharpTop = nil
        plain.boxSharpBottom = nil
        plain.focusLeft = nil
        plain.focusRight = nil
        plain.focusTop = nil
        plain.focusBottom = nil
        let line = MovementLog.csv([plain]).split(separator: "\n")[1]
        let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        for name in [
            "start_match_x_px", "start_match_y_px", "true_off_start_fields", "tracker_error_fields",
            "view_class", "guide_state", "guide_instruction", "guide_target_dx", "guide_target_dy",
            "guide_captures", "guide_axes_mapping", "box_sharp_left", "box_sharp_right",
            "box_sharp_top", "box_sharp_bottom", "focus_left", "focus_right", "focus_top",
            "focus_bottom",
        ] {
            let column = MovementLog.header.firstIndex(of: name) ?? -1
            XCTAssertEqual(fields[column], "", name)
        }
    }

    func testTextFieldsAreQuoted() {
        let csv = MovementLog.csv([row(label: "a, \"b\"")])
        XCTAssertTrue(csv.contains("\"a, \"\"b\"\"\""))
    }

    func testTheSpotAndCountingColumnsAreAppendedLast() {
        XCTAssertEqual(
            MovementLog.header.suffix(65).prefix(3), ["spot_mode", "spot_window", "touch_seconds"])
        XCTAssertEqual(
            MovementLog.header.suffix(49).prefix(18),
            [
                "event_detail", "detector_model", "det_drop_disc", "det_drop_big", "det_units",
                "frame_dt", "camera_fps", "exposure_ms", "iso", "thermal_state", "battery_level",
                "sharpness_ref", "sharpness_share", "pause_cause", "det_frame_seconds", "det_pre_ms",
                "det_infer_ms", "det_decode_ms",
            ])
        var logged = row()
        logged.spotMode = "brief_touch"
        logged.spotWindow = "in"
        logged.touchSeconds = 0.2
        logged.missedSpots = 2
        logged.coverageStep = 1.6
        logged.countingActive = true
        logged.detRan = true
        logged.detMilliseconds = 5.14
        logged.detFound = 3
        logged.countMapTotal = 7
        logged.event = "organism_counted"
        logged.eventDetail = "Volvox id=7"
        logged.detectorModel = "v2"
        logged.detDropDisc = 1
        logged.detDropBig = 0
        logged.detUnits = "ne"
        logged.frameDt = 0.1234
        logged.cameraFps = 19.6
        logged.exposureMs = 18.5
        logged.iso = 160
        logged.thermalState = "fair"
        logged.batteryLevel = 0.874
        logged.sharpnessRef = 2240.04
        logged.sharpnessShare = 0.2612
        logged.pauseCause = "index_and_sharpness"
        logged.detFrameSeconds = 12.3456
        logged.detPreMs = 3.04
        logged.detInferMs = 28.96
        logged.detDecodeMs = 0.52
        let fields = MovementLog.csv([logged]).split(separator: "\n")[1].split(
            separator: ",", omittingEmptySubsequences: false
        ).map(String.init)
        let index = { MovementLog.header.firstIndex(of: $0)! }
        XCTAssertEqual(fields[index("spot_mode")], "brief_touch")
        XCTAssertEqual(fields[index("spot_window")], "in")
        XCTAssertEqual(fields[index("touch_seconds")], "0.20")
        XCTAssertEqual(fields[index("missed_spots")], "2")
        XCTAssertEqual(fields[index("coverage_step")], "1.6")
        XCTAssertEqual(fields[index("counting_active")], "1")
        XCTAssertEqual(fields[index("det_ran")], "1")
        XCTAssertEqual(fields[index("det_ms")], "5.1")
        XCTAssertEqual(fields[index("det_found")], "3")
        XCTAssertEqual(fields[index("count_map_total")], "7")
        XCTAssertEqual(fields[index("event_detail")], "Volvox id=7")
        XCTAssertEqual(fields[index("detector_model")], "v2")
        XCTAssertEqual(fields[index("det_drop_disc")], "1")
        XCTAssertEqual(fields[index("det_drop_big")], "0")
        XCTAssertEqual(fields[index("det_units")], "ne")
        XCTAssertEqual(fields[index("frame_dt")], "0.123")
        XCTAssertEqual(fields[index("camera_fps")], "19.6")
        XCTAssertEqual(fields[index("exposure_ms")], "18.50")
        XCTAssertEqual(fields[index("iso")], "160")
        XCTAssertEqual(fields[index("thermal_state")], "fair")
        XCTAssertEqual(fields[index("battery_level")], "0.87")
        XCTAssertEqual(fields[index("sharpness_ref")], "2240.0")
        XCTAssertEqual(fields[index("sharpness_share")], "0.26")
        XCTAssertEqual(fields[index("pause_cause")], "index_and_sharpness")
        XCTAssertEqual(fields[index("det_frame_seconds")], "12.346")
        XCTAssertEqual(fields[index("det_pre_ms")], "3.0")
        XCTAssertEqual(fields[index("det_infer_ms")], "29.0")
        XCTAssertEqual(fields[index("det_decode_ms")], "0.5")
        XCTAssertEqual(fields.count, MovementLog.header.count)
    }

    /// Phase 2u: the edge-acceptance, prediction and camera-drop columns are appended last.
    func testThePhase2uColumnsAreAppendedLast() {
        // `knob_words` came after these, in Phase 3c, then the two heat columns (performance
        // step 3) and the two lens video columns,
        // the guide's four, and the stage branch's four.
        XCTAssertEqual(
            Array(MovementLog.header.suffix(31).prefix(5)),
            ["line_accept", "area_ahead_share", "predicted_edge_along", "expected_edge_ask", "camera_drops"])
        var logged = row()
        logged.lineState = "attached"
        logged.lineAccept = "area"
        logged.areaAheadShare = 0.0512
        logged.predictedEdgeAlong = -9.1234
        logged.expectedEdgeAsk = true
        logged.cameraDrops = 7
        let fields = MovementLog.csv([logged]).split(separator: "\n")[1].split(
            separator: ",", omittingEmptySubsequences: false
        ).map(String.init)
        XCTAssertEqual(fields.count, MovementLog.header.count)
        XCTAssertEqual(Array(fields.suffix(31).prefix(5)), ["area", "0.051", "-9.123", "1", "7"])
    }

    /// Performance step 3: the heat mode and the screen brightness come before the lens video's
    /// two columns.
    func testTheHeatModeAndScreenBrightnessComeBeforeTheLensVideoColumns() {
        var logged = row()
        logged.heatMode = "cool_down"
        logged.screenBrightness = 0.35
        let lines = MovementLog.csv([logged]).split(separator: "\n")
        let fields = lines[1].split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertEqual(fields.count, MovementLog.header.count)
        XCTAssertEqual(fields.suffix(25).prefix(2).map(String.init), ["cool_down", "0.35"])
    }

    func testTheLensVideoColumnsComeBeforeTheGuidesAndTheStages() {
        var logged = row()
        logged.lensRecording = true
        logged.videoDrops = 4
        let fields = MovementLog.csv([logged]).split(separator: "\n")[1].split(
            separator: ",", omittingEmptySubsequences: false
        ).map(String.init)
        XCTAssertEqual(fields.count, MovementLog.header.count)
        XCTAssertEqual(Array(fields.suffix(23).prefix(2)), ["1", "4"])
        XCTAssertEqual(
            Array(
                MovementLog.csv([row()]).split(separator: "\n")[1].split(
                    separator: ",", omittingEmptySubsequences: false
                ).suffix(23).prefix(2)), ["0", ""])
    }

    /// The focus pause's peak and turning hint come after the lens video's and the guide's.
    func testTheFocusPauseColumnsComeBeforeTheStageAngles() {
        XCTAssertEqual(Array(MovementLog.header.suffix(17).prefix(2)), ["focus_peak", "focus_hint"])
        var logged = row()
        logged.focusPeak = 0.7281
        logged.focusHint = "Try turning the other way"
        let fields = MovementLog.csv([logged]).split(separator: "\n")[1].split(
            separator: ",", omittingEmptySubsequences: false
        ).map(String.init)
        XCTAssertEqual(fields.count, MovementLog.header.count)
        XCTAssertEqual(Array(fields.suffix(17).prefix(2)), ["0.728", "Try turning the other way"])
    }

    /// The automated stage's servo angles are the last two columns, empty without the stage.
    func testTheStageAngleColumnsPrecedeTheFocusTilesColumns() {
        XCTAssertEqual(
            Array(MovementLog.header.suffix(15).prefix(2)), ["stage_angle_x", "stage_angle_y"])
        var logged = row()
        let plain = MovementLog.csv([logged]).split(separator: "\n")[1].split(
            separator: ",", omittingEmptySubsequences: false
        ).map(String.init)
        XCTAssertEqual(Array(plain.suffix(15).prefix(2)), ["", ""])
        logged.stageAngleX = 87
        logged.stageAngleY = 142
        let fields = MovementLog.csv([logged]).split(separator: "\n")[1].split(
            separator: ",", omittingEmptySubsequences: false
        ).map(String.init)
        XCTAssertEqual(fields.count, MovementLog.header.count)
        XCTAssertEqual(Array(fields.suffix(15).prefix(2)), ["87", "142"])
    }

    // MARK: Focus tiles

    private func focusReading() -> FocusTilesReading {
        FocusTilesReading(
            top: 1234.5678, topRatio: 2.5, topTiles: [3, 19, 20, 41], noise: 12.3456, used: 60,
            active: 9, tileFine: Array(repeating: nil, count: 64))
    }

    func testTheFocusTilesColumnsAreTheLastNineAndFilledFromTheReading() {
        XCTAssertEqual(
            Array(MovementLog.header.suffix(13).prefix(9)),
            [
                "focus_top", "focus_top_ratio", "focus_noise", "focus_tiles_used",
                "focus_tiles_active", "focus_top_tiles", "focus_tiles_ms", "focus_label",
                "focus_sweep",
            ])
        var logged = row()
        logged.focusTiles = focusReading()
        logged.focusTilesMs = 0.4321
        logged.focusLabel = "sharp"
        logged.focusSweep = true
        let fields = MovementLog.csv([logged]).split(separator: "\n")[1].split(
            separator: ",", omittingEmptySubsequences: false
        ).map(String.init)
        XCTAssertEqual(fields.count, MovementLog.header.count)
        XCTAssertEqual(
            Array(fields.suffix(13).prefix(9)),
            ["1235", "2.5", "12.35", "60", "9", "3 19 20 41", "0.4321", "sharp", "1"])
    }

    func testTheFocusTilesColumnsAreEmptyWithoutAReading() {
        let fields = MovementLog.csv([row()]).split(separator: "\n")[1].split(
            separator: ",", omittingEmptySubsequences: false
        ).map(String.init)
        XCTAssertEqual(Array(fields.suffix(13).prefix(9)), ["", "", "", "", "", "", "", "", "0"])
    }

    func testTheLastFourColumnsHoldTheDetailAndAll64Tiles() {
        XCTAssertEqual(
            Array(MovementLog.header.suffix(4)),
            ["focus_detail", "focus_detail_best", "focus_tile_fine", "focus_tile_coarse"])
        var logged = row()
        var fine = [Double?](repeating: nil, count: 64)
        var coarse = [Double?](repeating: nil, count: 64)
        fine[0] = 1234.5678
        fine[63] = 0.5
        coarse[0] = 7
        var reading = focusReading()
        reading.tileFine = fine
        reading.tileCoarse = coarse
        reading.detail = 6.789123
        logged.focusTiles = reading
        logged.focusDetailBest = 9.87654
        let fields = MovementLog.csv([logged]).split(separator: "\n")[1].split(
            separator: ",", omittingEmptySubsequences: false
        ).map(String.init)
        XCTAssertEqual(fields.count, MovementLog.header.count)
        XCTAssertEqual(fields[fields.count - 4], "6.789")
        XCTAssertEqual(fields[fields.count - 3], "9.877")
        let tiles = fields[fields.count - 2].split(separator: " ").map(String.init)
        XCTAssertEqual(tiles.count, 64)
        XCTAssertEqual(tiles[0], "1235")
        XCTAssertEqual(tiles[1], "-")
        XCTAssertEqual(tiles[63], "0.5")
        XCTAssertEqual(fields[fields.count - 1].split(separator: " ").count, 64)
        XCTAssertEqual(fields[fields.count - 1].split(separator: " ").first, "7")
    }

    func testTheLastFourColumnsAreEmptyWithoutAReading() {
        let fields = MovementLog.csv([row()]).split(separator: "\n")[1].split(
            separator: ",", omittingEmptySubsequences: false
        ).map(String.init)
        XCTAssertEqual(Array(fields.suffix(4)), ["", "", "", ""])
    }
}
