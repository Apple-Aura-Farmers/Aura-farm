import XCTest

@testable import AuraFarm

final class StageProtocolTests: XCTestCase {
    private func p(_ x: Int, _ y: Int) -> StagePoint { StagePoint(x: x, y: y) }

    func testCommandText() {
        XCTAssertEqual(StageCommand.status.text, "STATUS")
        XCTAssertEqual(StageCommand.mode(.auto).text, "MODE AUTO")
        XCTAssertEqual(StageCommand.mode(.manual).text, "MODE MANUAL")
        XCTAssertEqual(StageCommand.jog(.x, -5).text, "JOG X -5")
        XCTAssertEqual(StageCommand.jog(.y, 10).text, "JOG Y 10")
        XCTAssertEqual(StageCommand.goTo(.x, 120).text, "GOTO X 120")
        XCTAssertEqual(StageCommand.path([p(30, 30), p(150, 30)]).text, "PATH 30,30;150,30")
        XCTAssertEqual(StageCommand.start.text, "START")
        XCTAssertEqual(StageCommand.traverse.text, "TRAVERSE")
        XCTAssertEqual(StageCommand.stop.text, "STOP")
        XCTAssertEqual(StageCommand.resume.text, "RESUME")
        XCTAssertEqual(StageCommand.home.text, "HOME")
        XCTAssertEqual(StageCommand.end.text, "END")
    }

    func testValidation() throws {
        XCTAssertThrowsError(try StageCommand.goTo(.x, 181).validated())
        XCTAssertThrowsError(try StageCommand.goTo(.y, -1).validated())
        XCTAssertThrowsError(try StageCommand.path([p(0, 181)]).validated())
        XCTAssertThrowsError(try StageCommand.path([p(-5, 0)]).validated())
        XCTAssertThrowsError(try StageCommand.path([]).validated())
        let long = Array(repeating: p(180, 180), count: 40)
        XCTAssertThrowsError(try StageCommand.path(long).validated())
        XCTAssertFalse(StageCommand.pathFits(long))
        XCTAssertEqual(
            try StageCommand.path([p(30, 30), p(150, 30)]).validated(), "PATH 30,30;150,30")
        XCTAssertTrue(StageCommand.pathFits([p(30, 30)]))
    }

    func testPresetsValid() throws {
        for preset in StagePresetPath.allCases {
            XCTAssertTrue(StageCommand.pathFits(preset.points), preset.title)
            XCTAssertNoThrow(try StageCommand.path(preset.points).validated(), preset.title)
        }
    }

    func testParse() {
        XCTAssertEqual(StageReply.parse("OK MODE AUTO"), .ok("MODE AUTO"))
        XCTAssertEqual(StageReply.parse("ERR LIMIT 0-180"), .error("LIMIT 0-180"))
        XCTAssertEqual(StageReply.parse("POS X=100 Y=90"), .position(x: 100, y: 90))
        XCTAssertEqual(StageReply.parse("DONE X=90 Y=90"), .done(x: 90, y: 90))
        XCTAssertEqual(
            StageReply.parse("HELLO MANUAL IDLE X=90 Y=90"),
            .hello(mode: .manual, state: .idle, x: 90, y: 90))
        XCTAssertEqual(
            StageReply.parse("RESUMED X=30 Y=150 Q=5"), .resumed(x: 30, y: 150, queued: 5))
        XCTAssertEqual(
            StageReply.parse("MANUAL IDLE X=90 Y=90 Q=0"),
            .status(mode: .manual, state: .idle, x: 90, y: 90, queued: 0))
        XCTAssertEqual(
            StageReply.parse("  AUTO PAUSED X=12 Y=170 Q=3\r\n"),
            .status(mode: .auto, state: .paused, x: 12, y: 170, queued: 3))
    }

    func testParseGarbage() {
        XCTAssertEqual(StageReply.parse("hello?"), .unknown("hello?"))
        XCTAssertEqual(StageReply.parse(""), .unknown(""))
        XCTAssertEqual(StageReply.parse("POS X=abc"), .unknown("POS X=abc"))
    }

    func testFocusServoCommandsAndReply() throws {
        XCTAssertEqual(StageCommand.focusGoTo(120).text, "GOTO Z 120")
        XCTAssertEqual(StageCommand.focusJog(-5).text, "JOG Z -5")
        XCTAssertEqual(try StageCommand.focusGoTo(120).validated(), "GOTO Z 120")
        XCTAssertThrowsError(try StageCommand.focusGoTo(181).validated())
        XCTAssertThrowsError(try StageCommand.focusGoTo(-1).validated())
        XCTAssertEqual(StageReply.parse("ZPOS Z=87"), .focusPosition(z: 87))
        XCTAssertEqual(StageReply.parse("ZPOS"), .unknown("ZPOS"))
        XCTAssertEqual(StageReply.parse("ZPOS X=1"), .unknown("ZPOS X=1"))
        XCTAssertEqual(StageReply.parse("ZPOS Z=87 X=1"), .unknown("ZPOS Z=87 X=1"))
    }
}
