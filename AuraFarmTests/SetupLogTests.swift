import XCTest

@testable import AuraFarm

final class SetupLogTests: XCTestCase {
    func testTheHeaderAndARowHaveTheSameColumnsAndTheValuesFormat() {
        var alignment = AlignmentReading()
        alignment.found = true
        alignment.circle = FieldCircle(centre: CGPoint(x: 640.04, y: 360), radius: 280.55)
        alignment.clippedSides = [.right, .top]
        alignment.roundness = 0.9123
        alignment.evenness = 0.7
        alignment.darkestSector = 0
        alignment.brightestSector = 4
        alignment.saturatedShare = 0.0123
        alignment.glareRatio = 1.31
        alignment.score = 42.26
        alignment.problems = [.clipped, .glare]
        let focus = FocusReading(state: .nearPeak, current: 450, peak: 500, level: 0.9)
        let rows = [
            SetupLogRow(
                seconds: 1.234, step: .focus, alignment: alignment, focus: focus,
                tracker: SetupTrackerSample(
                    tracking: .paused, position: CGPoint(x: 0.3, y: -1.23456), boxSharpness: 17.04,
                    viewClass: .blank, stillSeconds: 2.5)),
            SetupLogRow(seconds: 2, step: .align, alignment: AlignmentReading(), focus: nil),
        ]
        let lines = SetupLog.csv(rows).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(
            lines[0],
            "seconds,step,found,circle_x,circle_y,circle_r,clipped_sides,roundness,evenness,darkest_sector,brightest_sector,saturated_share,glare_ratio,score,problems,focus_state,focus_current,focus_peak,focus_level,stage_step,stage_travel_fields,stage_tilt_deg,stage_skew_deg,tracking,position_x_fields,position_y_fields,box_sharpness,view_class,still_seconds"
        )
        let first = lines[1].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(first.count, SetupLog.header.count)
        let index = { SetupLog.header.firstIndex(of: $0)! }
        XCTAssertEqual(first[index("seconds")], "1.23")
        XCTAssertEqual(first[index("step")], "focus")
        XCTAssertEqual(first[index("found")], "1")
        XCTAssertEqual(first[index("circle_x")], "640.0")
        XCTAssertEqual(first[index("circle_r")], "280.6")
        XCTAssertEqual(first[index("clipped_sides")], "top right")
        XCTAssertEqual(first[index("roundness")], "0.912")
        XCTAssertEqual(first[index("darkest_sector")], "0")
        XCTAssertEqual(first[index("saturated_share")], "0.0123")
        XCTAssertEqual(first[index("score")], "42.3")
        XCTAssertEqual(first[index("problems")], "clipped glare")
        XCTAssertEqual(first[index("focus_state")], "near_peak")
        XCTAssertEqual(first[index("focus_level")], "0.900")
        XCTAssertEqual(first[index("tracking")], "paused")
        XCTAssertEqual(first[index("position_x_fields")], "0.300")
        XCTAssertEqual(first[index("position_y_fields")], "-1.235")
        XCTAssertEqual(first[index("box_sharpness")], "17.0")
        XCTAssertEqual(first[index("view_class")], "blank")
        XCTAssertEqual(first[index("still_seconds")], "2.50")
        let empty = lines[2].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(empty.count, SetupLog.header.count)
        XCTAssertEqual(empty[index("step")], "align")
        XCTAssertEqual(empty[index("found")], "0")
        XCTAssertEqual(empty[index("circle_x")], "")
        XCTAssertEqual(empty[index("focus_state")], "")
        XCTAssertEqual(empty[index("tracking")], "", "the tracker is not running at align")
        XCTAssertEqual(empty[index("still_seconds")], "")
    }
}
