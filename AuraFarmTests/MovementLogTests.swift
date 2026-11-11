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
            hopProgress: 0.5, stillSeconds: 1.234, offStartFrames: nil, fieldRegion: "auto-learned",
            analysisMilliseconds: 41.66, analyzedFps: 9.84, fieldOpenShare: 0.6234)
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
        XCTAssertEqual(MovementLog.header.suffix(11).first, "test")
        XCTAssertEqual(
            MovementLog.header.suffix(4),
            ["field_region", "analysis_ms", "analyzed_fps", "field_open_share"])
        XCTAssertEqual(fields[index("test")], "drift")
        XCTAssertEqual(fields[index("note")], "hand 10x")
        XCTAssertEqual(fields[index("speed_fraction")], "0.046")
        XCTAssertEqual(fields[index("status")], "too_fast")
        XCTAssertEqual(fields[index("still_seconds")], "1.23")
        XCTAssertEqual(fields[index("off_start_frames")], "")
        XCTAssertEqual(fields[index("field_region")], "auto-learned")
        XCTAssertEqual(fields[index("field_open_share")], "0.623")
        XCTAssertEqual(fields[index("analysis_ms")], "41.7")
        XCTAssertEqual(fields[index("analyzed_fps")], "9.8")
    }

    func testTextFieldsAreQuoted() {
        let csv = MovementLog.csv([row(label: "a, \"b\"")])
        XCTAssertTrue(csv.contains("\"a, \"\"b\"\"\""))
    }
}
