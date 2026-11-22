import XCTest

@testable import AuraFarm

final class StageRestartTests: XCTestCase {
    func testAnglesWithinADegreeAreNotARestart() {
        XCTAssertFalse(StageRestart.detected(saved: (60, 120), reported: (60, 120)))
        XCTAssertFalse(StageRestart.detected(saved: (60, 120), reported: (61, 119)))
    }

    func testMoreThanADegreeOnEitherServoIsARestart() {
        XCTAssertTrue(StageRestart.detected(saved: (60, 120), reported: (90, 90)))
        XCTAssertTrue(StageRestart.detected(saved: (60, 120), reported: (60, 122)))
        XCTAssertTrue(StageRestart.detected(saved: (60, 120), reported: (58, 120)))
    }

    func testTheWalkBackGoesYFirstThenXInPanelSizedSteps() {
        var angles = (x: 90, y: 90)
        let saved = (x: 83, y: 97)
        var moves: [(servo: StageAxis, angle: Int)] = []
        while let next = StageRestart.nextStep(from: angles, to: saved, chunk: 2) {
            XCTAssertLessThanOrEqual(abs(next.angle - (next.servo == .x ? angles.x : angles.y)), 2)
            moves.append(next)
            if next.servo == .x { angles.x = next.angle } else { angles.y = next.angle }
            XCTAssertLessThan(moves.count, 50)
        }
        XCTAssertEqual(angles.x, 83)
        XCTAssertEqual(angles.y, 97)
        // Y finishes (92, 94, 96, 97) before X starts (88, 86, 84, 83).
        XCTAssertEqual(moves.prefix(4).map(\.angle), [92, 94, 96, 97])
        XCTAssertTrue(moves.prefix(4).allSatisfy { $0.servo == .y })
        XCTAssertTrue(moves.dropFirst(4).allSatisfy { $0.servo == .x })
        XCTAssertEqual(moves.last?.angle, 83)
    }

    func testThereIsNothingToWalkWhenTheServosAreAlreadyBack() {
        XCTAssertNil(StageRestart.nextStep(from: (40, 50), to: (40, 50), chunk: 2))
    }
}
