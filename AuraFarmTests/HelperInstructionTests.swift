import XCTest

@testable import AuraFarm

final class HelperInstructionTests: XCTestCase {
    private let rule = KnobRule()
    private let left = CGPoint(x: -1, y: 0)
    private let right = CGPoint(x: 1, y: 0)
    private let up = CGPoint(x: 0, y: -1)
    private let v = CGPoint(x: 0.5, y: 0)

    private func card(
        _ instruction: GuideInstruction, arrow: CGPoint? = nil, asks: Bool = false
    ) -> HelperInstruction? {
        HelperInstruction.make(for: instruction, arrow: arrow, rule: rule, asksEdge: asks)
    }

    // MARK: The table

    func testEveryGuideInstructionMapsToOneCard() {
        // text, with an arrow to the left unless the case has none.
        let table: [(GuideInstruction, String?)] = [
            (.findSample, "Move onto the sample and focus"),
            (.travel(direction: left), "Bottom knob towards you"),
            (.move(toward: v), "Bottom knob towards you"),
            (.farAway(direction: left), "Bottom knob towards you"),
            (.aligned, "Hold still"),
            (.holding(progress: 0.4), "Hold still"),
            (.captured, nil),
            (.edgeGoBack(toward: v), "Back a little: bottom knob towards you"),
            (.edgeReached, "Edge found"),
            (.checkingEdge(progress: 0.5), "Hold still"),
            (.stillNoDetail(toward: v), "Turn the fine focus slowly until it's sharp"),
            (.checkEdge(toward: v), "Back a little: bottom knob towards you"),
            (.stageLimit, "The stage won't go further. Turning"),
            (.paused(.alignment), "The phone moved. Line it back up"),
            (.paused(.focus), "Turn the fine focus slowly until it's sharp"),
            (.lineAhead, "Bottom knob towards you"),
            (.edgeDetected, "Hold still"),
            (.edgeBehind(toward: v), "Back a little: bottom knob towards you"),
            (.lineLead(direction: left, nudge: false), "Bottom knob towards you"),
            (.expectedEdge, "Is this the edge of the sample?"),
            (.notAnEdge, "Bottom knob towards you"),
            (.nothingToFollow, "Back a little: bottom knob towards you"),
            (.tooFar, "Back a little: bottom knob towards you"),
            (.otherWay, "Back a little: bottom knob towards you"),
            (.missedSpot(toward: v), "Back a little: bottom knob towards you"),
            (.refocus, "Turn the fine focus slowly until it's sharp"),
            (.slowDown, "Slower"),
            (.finished, "Done"),
        ]
        for (instruction, expected) in table {
            XCTAssertEqual(card(instruction, arrow: left)?.text, expected, "\(instruction)")
        }
    }

    func testNothingToFollowWithNoDirectionIsRefocus() {
        XCTAssertEqual(card(.nothingToFollow)?.text, "Turn the fine focus slowly until it's sharp")
    }

    func testATurnWithNoArrowKeepsTheCardOnScreen() {
        XCTAssertNil(card(.move(toward: v), arrow: nil))
    }

    func testTheQuestionReplacesWhateverElseWhileTheEdgeIsAsked() {
        XCTAssertEqual(card(.edgeDetected, arrow: up, asks: true), .question)
        XCTAssertEqual(card(.holding(progress: 0.2), arrow: up, asks: true), .question)
        XCTAssertEqual(card(.expectedEdge), .question)
        // The run being over is not a question.
        XCTAssertEqual(card(.finished, asks: true), .finished)
    }

    func testStopCarriesItsProgressRing() {
        XCTAssertEqual(card(.holding(progress: 0.4))?.progress ?? -1, 0.4, accuracy: 1e-9)
        XCTAssertEqual(card(.checkingEdge(progress: 7))?.progress ?? -1, 1, accuracy: 1e-9)
    }

    // MARK: Steadiness

    func testABlipOfAnotherTurnDoesNotChangeTheCard() throws {
        var steady = CardSteadiness()
        let first = try XCTUnwrap(card(.move(toward: v), arrow: left))
        let blip = try XCTUnwrap(card(.move(toward: v), arrow: right))
        XCTAssertEqual(steady.offer(first, at: 0).card, first)
        // 0.3 s of the other way, then back.
        XCTAssertEqual(steady.offer(blip, at: 0.1).card, first)
        XCTAssertEqual(steady.offer(blip, at: 0.4).card, first)
        XCTAssertEqual(steady.offer(first, at: 0.5).card, first)
        // The wait starts again after the blip.
        XCTAssertEqual(steady.offer(blip, at: 0.6).card, first)
        XCTAssertEqual(steady.offer(blip, at: 1.3).card, first, "0.7 s is not enough")
        let changed = steady.offer(blip, at: 1.4)
        XCTAssertEqual(changed.card, blip)
        XCTAssertTrue(changed.isNew)
    }

    func testStopAndTheQuestionAndPhoneMovedAndDoneShowAtOnce() throws {
        for immediate in [
            HelperInstruction.stop(progress: nil, note: nil), .question, .phoneMoved, .finished,
        ] {
            var steady = CardSteadiness()
            let turn = try XCTUnwrap(card(.move(toward: v), arrow: left))
            _ = steady.offer(turn, at: 0)
            let result = steady.offer(immediate, at: 0.05)
            XCTAssertEqual(result.card, immediate)
            XCTAssertTrue(result.isNew)
        }
    }

    func testTheRingMovingIsTheSameCardAndNotNew() {
        var steady = CardSteadiness()
        _ = steady.offer(.stop(progress: 0.1, note: nil), at: 0)
        let next = steady.offer(.stop(progress: 0.5, note: nil), at: 0.2)
        XCTAssertEqual(next.card.progress ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertFalse(next.isNew, "no second tap for a ring moving")
    }

    func testANoticeStaysBeforeAnOrdinaryCardReplacesIt() throws {
        var steady = CardSteadiness()
        _ = steady.offer(.edgeFound, at: 0)
        let turn = try XCTUnwrap(card(.move(toward: v), arrow: left))
        XCTAssertEqual(steady.offer(turn, at: 1.0).card, .edgeFound)
        XCTAssertEqual(steady.offer(turn, at: 1.6).card, .edgeFound, "not yet steady for 0.8 s")
        XCTAssertEqual(steady.offer(turn, at: 1.9).card, turn, "steady, and the notice is over")
        XCTAssertEqual(steady.offer(.edgeFound, at: 2.0).card, .edgeFound, "a notice is at once")
    }

    // MARK: Haptics

    func testEachCardHasOneHapticPattern() throws {
        let turn = try XCTUnwrap(card(.move(toward: v), arrow: left))
        XCTAssertEqual(HelperInstruction.slower.haptic, .twoLight)
        XCTAssertEqual(HelperInstruction.stop(progress: nil, note: nil).haptic, .firm)
        XCTAssertEqual(HelperInstruction.question.haptic, .firm)
        XCTAssertEqual(try XCTUnwrap(card(.tooFar, arrow: left)).haptic, .threeLight)
        XCTAssertEqual(HelperInstruction.edgeFound.haptic, .success)
        XCTAssertEqual(HelperInstruction.finished.haptic, .longSuccess)
        XCTAssertEqual(turn.haptic, .none)
        XCTAssertEqual(HelperHaptic.twoLight.taps.count, 2)
        XCTAssertEqual(HelperHaptic.threeLight.taps.count, 3)
        XCTAssertEqual(HelperHaptic.firm.taps.count, 1)
        XCTAssertGreaterThan(
            HelperHaptic.longSuccess.taps.count, HelperHaptic.success.taps.count)
        XCTAssertTrue(HelperHaptic.none.taps.isEmpty)
    }

    // MARK: The page's presenter, in order

    private func input(
        _ seconds: Double, _ instruction: GuideInstruction, arrow: CGPoint? = nil,
        asks: Bool = false, column: Int = 1, last: Bool = false, height: Double? = nil,
        speed: Double = 0.02, near: Bool = false, captures: Int = 0, finished: Bool = false
    ) -> GuidedScanInput {
        GuidedScanInput(
            seconds: seconds, instruction: instruction, arrow: arrow, asksEdge: asks, column: column,
            lastColumn: last, slipHeightFields: height, speedFraction: speed, spotNearCross: near,
            captureCount: captures, isFinished: finished)
    }

    func testAScriptedRunGivesTheCardsHapticsAndColumnTextInOrder() {
        var presenter = GuidedScanPresenter()
        var shown: [(String?, HelperHaptic, String)] = []
        func step(_ input: GuidedScanInput) {
            let display = presenter.present(input)
            shown.append((display.card?.text, display.haptic, display.columnText))
        }

        step(input(0.0, .move(toward: v), arrow: left))
        step(input(0.1, .move(toward: v), arrow: left))
        // A spot is ticked: the card stays, one light tap.
        step(input(0.2, .captured, arrow: left, captures: 1))
        // Too fast: "Slower", but only after it has held for 0.8 s.
        step(input(0.3, .move(toward: v), arrow: left, speed: 0.15, captures: 1))
        step(input(1.2, .move(toward: v), arrow: left, speed: 0.15, captures: 1))
        // The line is at the cross and the edge is asked.
        step(input(1.3, .edgeDetected, arrow: left, asks: true, captures: 1))
        step(input(1.4, .edgeReached, captures: 1))
        step(input(2.0, .finished, column: 2, captures: 1, finished: true))

        XCTAssertEqual(shown[0].0, "Bottom knob towards you")
        XCTAssertEqual(shown[0].1, .none)
        XCTAssertEqual(shown[0].2, "Column 1 of 9")
        XCTAssertEqual(shown[1].0, "Bottom knob towards you")
        XCTAssertEqual(shown[2].0, "Bottom knob towards you", "captured keeps the card")
        XCTAssertEqual(shown[2].1, .oneLight, "with the spot-tick haptic")
        XCTAssertEqual(shown[3].0, "Bottom knob towards you", "0.0 s of too fast so far")
        XCTAssertEqual(shown[4].0, "Slower")
        XCTAssertEqual(shown[4].1, .twoLight)
        XCTAssertEqual(shown[5].0, "Is this the edge of the sample?")
        XCTAssertEqual(shown[5].1, .firm)
        XCTAssertEqual(shown[6].0, "Edge found")
        XCTAssertEqual(shown[6].1, .success)
        XCTAssertEqual(shown[7].0, "Done")
        XCTAssertEqual(shown[7].1, .longSuccess)
        XCTAssertEqual(shown[7].2, "Column 2 of 9")
    }

    func testTheLastColumnIsSaidOnceAndTheCountBecomesReal() {
        var presenter = GuidedScanPresenter()
        _ = presenter.present(input(0, .move(toward: v), arrow: left, column: 8))
        let last = presenter.present(input(1, .move(toward: v), arrow: left, column: 9, last: true))
        XCTAssertEqual(last.card, .lastColumn)
        XCTAssertEqual(last.columnText, "Column 9 of 9")
        let after = presenter.present(input(1.2, .move(toward: v), arrow: left, column: 9, last: true))
        XCTAssertEqual(after.card, .lastColumn, "kept while the notice is up")
        XCTAssertEqual(after.haptic, .none, "said once")
    }

    // MARK: Columns and speed

    func testTheDefaultSlipGivesNineColumnsAtEverySecondAndSeventeenAtEvery() {
        let count = ColumnCount()
        XCTAssertEqual(count.total(step: 1.6), 9)
        XCTAssertEqual(count.total(step: 0.8), 17)
    }

    func testTheCountIsMeasuredAfterColumnOneAndRealAtTheEnd() {
        let count = ColumnCount()
        // A taller slip (15.1 fields): floor((15.1 - 1.2) / 1.6) + 1 = 9; 15.8 gives 10.
        XCTAssertEqual(count.shown(step: 1.6, measuredHeightFields: 15.1, column: 1, isLastColumn: false), 9)
        XCTAssertEqual(count.shown(step: 1.6, measuredHeightFields: 15.8, column: 1, isLastColumn: false), 10)
        XCTAssertEqual(count.shown(step: 1.6, measuredHeightFields: 13.6, column: 1, isLastColumn: false), 8)
        XCTAssertEqual(count.shown(step: 1.6, measuredHeightFields: nil, column: 1, isLastColumn: false), 9)
        // The last column found: that is the count.
        XCTAssertEqual(count.shown(step: 1.6, measuredHeightFields: 15.8, column: 7, isLastColumn: true), 7)
        // Never "Column 10 of 9".
        XCTAssertEqual(count.shown(step: 1.6, measuredHeightFields: nil, column: 10, isLastColumn: false), 10)
    }

    func testTheSpeedBandUsesTheExistingLimits() {
        let touch = BriefTouchThresholds().maxTouchSpeedFraction
        let comfortable = MovementIndicatorThresholds().comfortableSpeedFraction
        let fast = MovementIndicatorThresholds().tooFastSpeedFraction
        XCTAssertLessThan(touch, comfortable + 1, "sanity")
        // Away from a spot: green up to the comfortable limit.
        XCTAssertEqual(SpeedBand.of(speedFraction: comfortable, nearCross: false), .green)
        XCTAssertEqual(SpeedBand.of(speedFraction: comfortable + 0.01, nearCross: false), .amber)
        // Near the cross: the brief-touch limit.
        XCTAssertEqual(SpeedBand.of(speedFraction: touch, nearCross: true), .green)
        XCTAssertEqual(SpeedBand.of(speedFraction: touch + 0.01, nearCross: true), .amber)
        XCTAssertEqual(SpeedBand.of(speedFraction: fast, nearCross: false), .red)
        XCTAssertEqual(SpeedBand.of(speedFraction: fast, nearCross: true), .red)
        XCTAssertFalse(SpeedBand.green.asksForSlower)
        XCTAssertTrue(SpeedBand.amber.asksForSlower)
        XCTAssertTrue(SpeedBand.red.asksForSlower)
    }
}
