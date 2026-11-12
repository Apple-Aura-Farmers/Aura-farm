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
            guideTargetDx: 0.5, guideTargetDy: -0.8, guideCaptures: 7)
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
            MovementLog.header.suffix(20).prefix(7),
            [
                "box_brightness", "box_sharpness", "box_contrast", "reading", "predicted_streak",
                "no_detail", "blind_stretches",
            ])
        XCTAssertEqual(
            MovementLog.header.suffix(13),
            [
                "start_match_x_px", "start_match_y_px", "true_off_start_fields",
                "tracker_error_fields", "blank_returns_matched", "blank_returns_unmatched",
                "blank_return", "view_class", "guide_state", "guide_instruction",
                "guide_target_dx", "guide_target_dy", "guide_captures",
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
        let line = MovementLog.csv([plain]).split(separator: "\n")[1]
        let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        for name in [
            "start_match_x_px", "start_match_y_px", "true_off_start_fields", "tracker_error_fields",
            "view_class", "guide_state", "guide_instruction", "guide_target_dx", "guide_target_dy",
            "guide_captures",
        ] {
            let column = MovementLog.header.firstIndex(of: name) ?? -1
            XCTAssertEqual(fields[column], "", name)
        }
    }

    func testTextFieldsAreQuoted() {
        let csv = MovementLog.csv([row(label: "a, \"b\"")])
        XCTAssertTrue(csv.contains("\"a, \"\"b\"\"\""))
    }
}
