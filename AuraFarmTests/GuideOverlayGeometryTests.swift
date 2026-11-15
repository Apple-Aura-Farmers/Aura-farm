import XCTest

@testable import AuraFarm

final class GuideOverlayGeometryTests: XCTestCase {
    private let centre = CGPoint(x: 200, y: 220)
    private let ppf = 100.0
    private let radius = 150.0

    private func make(
        _ instruction: GuideInstruction, target: CGPoint? = nil, tracking: TrackingState = .tracking,
        position: CGPoint = .zero, finished: Bool = false
    ) -> GuideOverlayModel {
        let step = GuideStep(
            instruction: instruction, target: target, capture: nil, stateName: "x", column: 1,
            isFinished: finished, finishReason: nil)
        return GuideOverlayModel.make(
            step: step, position: position, tracking: tracking, centre: centre, pointsPerField: ppf,
            fieldRadius: radius, alignToleranceFields: 0.15)
    }

    func testANearTargetIsACrossAtTheRightPoint() {
        let model = make(.move(toward: CGPoint(x: 0.5, y: -0.25)), target: CGPoint(x: 0.5, y: -0.25))
        XCTAssertEqual(model.mark, .cross(at: CGPoint(x: 250, y: 195), tone: .move))
        XCTAssertEqual(model.toleranceRadius, 15, accuracy: 1e-9)
        XCTAssertEqual(model.centre, centre)
    }

    func testTheCrossIsRelativeToThePosition() {
        let model = make(
            .move(toward: CGPoint(x: 0.5, y: 0)), target: CGPoint(x: 2, y: 1),
            position: CGPoint(x: 1.5, y: 1))
        XCTAssertEqual(model.mark, .cross(at: CGPoint(x: 250, y: 220), tone: .move))
    }

    func testAFarTargetIsAnArrowPinnedOnTheCircle() throws {
        let model = make(.farAway(direction: CGPoint(x: 0, y: 1)), target: CGPoint(x: 0, y: 2.4))
        guard case .pinnedArrow(let at, let angle, let tone, let distance) = model.mark else {
            return XCTFail("expected an arrow, got \(model.mark)")
        }
        XCTAssertEqual(Double(at.x), 200, accuracy: 1e-6)
        XCTAssertEqual(Double(at.y), 220 + radius - 14, accuracy: 1e-6)
        XCTAssertEqual(angle, .pi / 2, accuracy: 1e-9, "down the screen")
        XCTAssertEqual(tone, .move)
        XCTAssertEqual(try XCTUnwrap(distance), 2.4, accuracy: 1e-9)
    }

    func testPausedOrMatchingNeverDrawsACross() {
        for state in [TrackingState.paused, .matching] {
            let model = make(
                .move(toward: CGPoint(x: 0.3, y: 0)), target: CGPoint(x: 0.3, y: 0), tracking: state)
            guard case .pinnedArrow = model.mark else {
                return XCTFail("\(state) drew \(model.mark)")
            }
        }
    }

    func testTravelLeftIsAnArrowPointingLeft() {
        let model = make(.travel(direction: CGPoint(x: -1, y: 0)))
        guard case .pinnedArrow(let at, let angle, _, let distance) = model.mark else {
            return XCTFail("expected an arrow, got \(model.mark)")
        }
        XCTAssertEqual(abs(angle), .pi, accuracy: 1e-9)
        XCTAssertEqual(Double(at.x), 200 - (radius - 14), accuracy: 1e-6)
        XCTAssertNil(distance)
    }

    func testGoBackPointsTheWayWhilePaused() {
        let model = make(.edgeGoBack(toward: CGPoint(x: 0, y: -1)), tracking: .paused)
        guard case .pinnedArrow(_, let angle, _, _) = model.mark else {
            return XCTFail("expected an arrow, got \(model.mark)")
        }
        XCTAssertEqual(angle, -.pi / 2, accuracy: 1e-9, "up the screen")
    }

    func testTooFarAndOtherWayAreWrongWay() {
        let target = CGPoint(x: 0.4, y: 0)
        XCTAssertEqual(
            make(.tooFar, target: target).mark, .cross(at: CGPoint(x: 240, y: 220), tone: .wrongWay))
        guard case .cross(_, let tone) = make(.otherWay, target: target).mark else {
            return XCTFail("expected a cross")
        }
        XCTAssertEqual(tone, .wrongWay)
        XCTAssertEqual(GuideOverlayModel.tone(of: .slowDown), .warning)
        XCTAssertEqual(GuideOverlayModel.tone(of: .aligned), .onTarget)
        XCTAssertEqual(GuideOverlayModel.tone(of: .holding(progress: 0.2)), .onTarget)
    }

    func testHoldingGivesProgressAndCapturedGivesTheFlash() {
        let holding = make(.holding(progress: 0.6), target: .zero)
        XCTAssertEqual(try XCTUnwrap(holding.holdProgress), 0.6, accuracy: 1e-9)
        XCTAssertFalse(holding.justCaptured)
        XCTAssertNil(make(.aligned, target: .zero).holdProgress)
        XCTAssertTrue(make(.captured, target: .zero).justCaptured)
        XCTAssertTrue(make(.finished, finished: true).isFinished)
        XCTAssertEqual(make(.finished).mark, .none)
    }

    func testCheckingTheEdgeKeepsTheMarkAndShowsTheProgress() throws {
        let step = GuideStep(
            instruction: .checkingEdge(progress: 0.4), target: nil, capture: nil, stateName: "x",
            column: 1, isFinished: false, finishReason: nil)
        let model = GuideOverlayModel.make(
            step: step, position: .zero, tracking: .tracking, centre: centre, pointsPerField: ppf,
            fieldRadius: radius, alignToleranceFields: 0.15, heading: CGPoint(x: -1, y: 0))
        XCTAssertEqual(try XCTUnwrap(model.checkProgress), 0.4, accuracy: 1e-9)
        XCTAssertNil(model.holdProgress)
        guard case .pinnedArrow(_, let angle, let tone, _) = model.mark else {
            return XCTFail("expected the travel arrow, got \(model.mark)")
        }
        XCTAssertEqual(abs(angle), .pi, accuracy: 1e-9)
        XCTAssertEqual(tone, .move)
        XCTAssertEqual(model.line, "Checking edge… hold still")
    }

    func testRefocusIsTheWarningToneAndKeepsTheTarget() {
        let model = make(.refocus, target: CGPoint(x: 0.4, y: 0))
        XCTAssertEqual(model.mark, .cross(at: CGPoint(x: 240, y: 220), tone: .warning))
        XCTAssertNil(model.checkProgress)
    }

    func testEveryInstructionHasHelperWording() {
        let all: [GuideInstruction] = [
            .findSample, .travel(direction: .zero), .move(toward: .zero), .farAway(direction: .zero),
            .aligned, .holding(progress: 0), .captured, .edgeGoBack(toward: .zero),
            .stillNoDetail(toward: .zero), .checkingEdge(progress: 0.5), .tooFar, .otherWay,
            .refocus, .slowDown, .finished,
        ]
        for instruction in all {
            XCTAssertFalse(instruction.helperText.isEmpty, "\(instruction)")
            XCTAssertNotEqual(instruction.helperText, "Other way")
            XCTAssertNotEqual(instruction.helperText, "Too far")
        }
        XCTAssertEqual(GuideInstruction.tooFar.helperText, "Turn back toward the cross")
        XCTAssertEqual(GuideInstruction.tooFar.csvName, "too_far")
        XCTAssertEqual(GuideInstruction.otherWay.debugText, "Other way")
    }
}
