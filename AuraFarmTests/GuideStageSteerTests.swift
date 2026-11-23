import XCTest

@testable import AuraFarm

final class GuideStageSteerTests: XCTestCase {
    func testTravelWithoutTargetIsUnit() throws {
        let v = try XCTUnwrap(
            GuideInstruction.travel(direction: CGPoint(x: 3, y: 4)).stageSteer(
                target: nil, heading: nil))
        XCTAssertEqual(v.x, 0.6, accuracy: 1e-9)
        XCTAssertEqual(v.y, 0.8, accuracy: 1e-9)
        XCTAssertNil(
            GuideInstruction.travel(direction: .zero).stageSteer(target: nil, heading: nil))
    }

    func testTargetWins() {
        let target = CGPoint(x: 2, y: -1)
        XCTAssertEqual(
            GuideInstruction.travel(direction: CGPoint(x: 1, y: 0)).stageSteer(
                target: target, heading: nil), target)
        XCTAssertEqual(
            GuideInstruction.move(toward: CGPoint(x: 9, y: 9)).stageSteer(
                target: target, heading: nil), target)
    }

    func testNoMove() {
        let target = CGPoint(x: 1, y: 1)
        for instruction in [
            GuideInstruction.paused(.alignment), .checkingEdge(progress: 0.5), .edgeDetected,
        ] {
            XCTAssertNil(instruction.stageSteer(target: target, heading: target))
        }
    }

    func testLineAheadUsesHeading() throws {
        let v = try XCTUnwrap(
            GuideInstruction.lineAhead.stageSteer(target: nil, heading: CGPoint(x: 0, y: -2)))
        XCTAssertEqual(v.x, 0, accuracy: 1e-9)
        XCTAssertEqual(v.y, -1, accuracy: 1e-9)
        XCTAssertNil(GuideInstruction.lineAhead.stageSteer(target: nil, heading: nil))
    }
}
