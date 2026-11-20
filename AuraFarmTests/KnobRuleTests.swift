import XCTest

@testable import AuraFarm

final class KnobRuleTests: XCTestCase {
    private func words(_ x: Double, _ y: Double, rule: KnobRule = KnobRule()) -> String? {
        rule.words(forArrowDirection: CGPoint(x: x, y: y))?.text
    }

    func testTheFourArrowsGiveTheUsersWords() {
        XCTAssertEqual(words(-1, 0), "Bottom knob towards you", "arrow left")
        XCTAssertEqual(words(1, 0), "Bottom knob away from you", "arrow right")
        XCTAssertEqual(words(0, -1), "Top knob towards you", "arrow up")
        XCTAssertEqual(words(0, 1), "Top knob away from you", "arrow down")
    }

    func testAnArrowNearlyOnAnAxisIsStillThatAxis() {
        // The straightened picture leaves a few degrees: 10 degrees off is still "left".
        XCTAssertEqual(words(-1, 0.17), "Bottom knob towards you")
        XCTAssertEqual(words(0.17, -1), "Top knob towards you")
    }

    func testADiagonalAsksForALittleOfTheOtherKnob() {
        XCTAssertEqual(
            words(-1, -1), "Bottom knob towards you and a little of the top knob",
            "45 degrees off both axes")
        XCTAssertEqual(
            words(1, 1.2), "Top knob away from you and a little of the bottom knob",
            "mostly down")
        // 30 degrees exactly is not more than 30.
        XCTAssertEqual(words(-1, tan(30 * .pi / 180)), "Bottom knob towards you")
        XCTAssertTrue(
            words(-1, tan(31 * .pi / 180))?.hasSuffix("a little of the top knob") ?? false)
    }

    func testNoDirectionGivesNoWords() {
        XCTAssertNil(words(0, 0))
    }

    func testSwapKnobsMakesTheTopKnobTheXKnob() {
        let rule = KnobRule(xKnob: .top)
        XCTAssertEqual(words(-1, 0, rule: rule), "Top knob towards you")
        XCTAssertEqual(words(0, -1, rule: rule), "Bottom knob towards you")
        XCTAssertEqual(words(0, 1, rule: rule), "Bottom knob away from you")
    }

    func testReverseXAndReverseYFlipOnlyTheirOwnAxis() {
        let reverseX = KnobRule(reversesX: true)
        XCTAssertEqual(words(-1, 0, rule: reverseX), "Bottom knob away from you")
        XCTAssertEqual(words(0, -1, rule: reverseX), "Top knob towards you")
        let reverseY = KnobRule(reversesY: true)
        XCTAssertEqual(words(0, -1, rule: reverseY), "Top knob away from you")
        XCTAssertEqual(words(-1, 0, rule: reverseY), "Bottom knob towards you")
    }

    func testTheWordsFollowBackALittle() {
        let card = HelperInstruction.backALittle(
            KnobRule().words(forArrowDirection: CGPoint(x: 1, y: 0))!)
        XCTAssertEqual(card.text, "Back a little: bottom knob away from you")
    }

    // MARK: Through the overlay's own geometry

    private let centre = CGPoint(x: 200, y: 220)

    /// The arrow as the overlay draws it for a guide step whose target is `fields` away on the
    /// displayed picture.
    private func drawnArrow(
        _ instruction: GuideInstruction, target: CGPoint?
    ) throws -> CGPoint {
        let step = GuideStep(
            instruction: instruction, target: target, capture: nil, stateName: "x", column: 1,
            isFinished: false, finishReason: nil)
        let model = GuideOverlayModel.make(
            step: step, position: .zero, tracking: .tracking, centre: centre, pointsPerField: 100,
            fieldRadius: 150, alignToleranceFields: 0.15)
        XCTAssertEqual(model.instruction, instruction)
        return try XCTUnwrap(model.arrowDirection)
    }

    func testAScreenLeftTargetIsDrawnLeftAndSaysBottomKnobTowardsYou() throws {
        let toward = CGPoint(x: -0.5, y: 0)
        let arrow = try drawnArrow(.move(toward: toward), target: toward)
        XCTAssertLessThan(arrow.x, 0)
        XCTAssertEqual(
            KnobRule().words(forArrowDirection: arrow)?.text, "Bottom knob towards you")
    }

    func testAFarArrowAndATravelArrowAreReadAsDrawn() throws {
        let right = try drawnArrow(.travel(direction: CGPoint(x: 1, y: 0)), target: nil)
        XCTAssertEqual(KnobRule().words(forArrowDirection: right)?.text, "Bottom knob away from you")
        let up = try drawnArrow(.farAway(direction: CGPoint(x: 0, y: -1)), target: CGPoint(x: 0, y: -2.4))
        XCTAssertEqual(KnobRule().words(forArrowDirection: up)?.text, "Top knob towards you")
        let down = try drawnArrow(.lineLead(direction: CGPoint(x: 0, y: 1), nudge: false), target: nil)
        XCTAssertEqual(KnobRule().words(forArrowDirection: down)?.text, "Top knob away from you")
    }

    /// The camera's frame axes go through the screen mapping the page uses (rotate 90 degrees
    /// left) before the guide sees them, so the words are about what the helper sees: a frame
    /// +y is screen right, a frame +x is screen up.
    func testTheRotateLeftMappingGivesTheWordsForWhatIsOnScreen() throws {
        let mapping = ScreenMapping.rotateLeft
        let cases: [(frame: CGPoint, words: String)] = [
            (CGPoint(x: 0, y: 1), "Bottom knob away from you"),  // screen right
            (CGPoint(x: 0, y: -1), "Bottom knob towards you"),  // screen left
            (CGPoint(x: 1, y: 0), "Top knob towards you"),  // screen up
            (CGPoint(x: -1, y: 0), "Top knob away from you"),  // screen down
        ]
        for (frame, expected) in cases {
            let screen = mapping.onScreen(frame, mirrored: false)
            let arrow = try drawnArrow(.move(toward: screen), target: screen)
            XCTAssertEqual(KnobRule().words(forArrowDirection: arrow)?.text, expected, "\(frame)")
        }
    }

    func testAnXAxisNearerVerticalThanHorizontalIsAMismatch() {
        XCTAssertFalse(KnobRule.xAxisIsVertical(CGPoint(x: 0.99, y: 0.17)))
        XCTAssertTrue(KnobRule.xAxisIsVertical(CGPoint(x: 0.2, y: 0.98)))
    }

    func testTheKnobWordsColumnIsFollowedOnlyByTheHeatAndLensVideoColumns() {
        // `heat_mode` and `screen_brightness` (performance step 3), then the lens video's two, then the line crossing columns.
        XCTAssertEqual(
            Array(MovementLog.header.suffix(7).prefix(5)),
            ["knob_words", "heat_mode", "screen_brightness", "lens_recording", "video_drops"])
    }
}
