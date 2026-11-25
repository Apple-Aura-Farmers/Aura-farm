import CoreGraphics
import XCTest

@testable import AuraFarm

/// Phase 4a-fix 3: the edge question on the card always applies to the question shown, and the
/// End run menu offers what is valid.
final class EdgeQuestionTests: XCTestCase {
    private let snapshot = EdgeQuestionSnapshot.line(point: CGPoint(x: -2, y: 0), angleDegrees: 0)

    // MARK: The book

    func testAQuestionIsRaisedKeptAndAnsweredOnce() {
        var book = EdgeQuestionBook()
        XCTAssertNil(book.currentID)
        book.update(asking: true, snapshot: snapshot, seconds: 1)
        XCTAssertEqual(book.currentID, 1)
        book.update(asking: true, snapshot: snapshot, seconds: 1.5)
        XCTAssertEqual(book.currentID, 1, "the same ask is the same question")
        XCTAssertEqual(book.answer(id: 1)?.snapshot, snapshot)
        XCTAssertNil(book.currentID)
        XCTAssertNil(book.answer(id: 1), "answered: a second tap is late")
    }

    func testAQuestionStaysAnswerableForAWhileAfterTheAskStopsThenExpires() {
        var book = EdgeQuestionBook()
        book.update(asking: true, snapshot: snapshot, seconds: 1)
        book.update(asking: false, snapshot: nil, seconds: 3)
        XCTAssertEqual(book.currentID, 1, "the line drifted off the cross; the card is still live")
        book.update(asking: false, snapshot: nil, seconds: 5.5)
        XCTAssertNil(book.currentID, "expired")
        XCTAssertNil(book.answer(id: 1))
    }

    func testAReplacedQuestionIsLate() {
        var book = EdgeQuestionBook()
        book.update(asking: true, snapshot: snapshot, seconds: 1)
        book.update(asking: false, snapshot: nil, seconds: 9)
        book.update(asking: true, snapshot: snapshot, seconds: 12)
        XCTAssertEqual(book.currentID, 2)
        XCTAssertNil(book.answer(id: 1), "the old question was replaced")
        XCTAssertNotNil(book.answer(id: 2))
    }

    func testTheRouteSettlingTheEdgeItselfClosesTheQuestion() {
        var book = EdgeQuestionBook()
        book.update(asking: true, snapshot: snapshot, seconds: 1)
        book.close()
        XCTAssertNil(book.answer(id: 1))
    }

    // MARK: The route

    private let left = ScriptedRoute.left

    private func line(_ offset: Double) -> EdgeLine {
        EdgeLine(
            strength: 30, coverage: 1, longestRun: 8, angleDegrees: 0, offsetFields: offset,
            sign: 1, slideResidualFields: nil, path: [], isCandidate: true, beforeEnergy: nil,
            beyondEnergy: nil)
    }

    /// The left-edge line is at the cross and the guide asks; returns the route and the question.
    private func askingRoute() throws -> (ScriptedRoute, EdgeQuestionSnapshot) {
        let route = ScriptedRoute(fullCoverSlip: true, asksEdges: true)
        route.feed(move: left, times: 10)
        var offset = 1.0
        while offset >= 0.1 - 1e-9 {
            route.feed(
                ScriptedRoute.Frame(line: EdgeLineFixtures.line(offset, residual: 0.05)), move: left)
            offset -= 0.1
        }
        route.feed(
            ScriptedRoute.Frame(still: true, line: EdgeLineFixtures.line(0.1, residual: nil)), times: 5)
        XCTAssertTrue(route.last.edge.lineAtCross)
        return (route, try XCTUnwrap(route.guide.edgeQuestionSnapshot))
    }

    /// The line has left the cross by the time of the tap: nothing at the cross any more.
    private func drift(_ route: ScriptedRoute) {
        route.feed(ScriptedRoute.Frame(still: true), move: ScriptedRoute.right, times: 6)
        XCTAssertFalse(route.last.edge.lineAtCross)
    }

    func testYesAfterTheLineHasDriftedOffTheCrossStillConfirmsTheCapturedEdge() throws {
        let (route, question) = try askingRoute()
        drift(route)
        route.seconds += 0.1
        let step = try XCTUnwrap(
            route.guide.answerEdgeQuestion(
                question, .yes, route.reading(ScriptedRoute.Frame(still: true))))
        XCTAssertEqual(step.instruction, .edgeReached)
        XCTAssertEqual(route.guide.edgesReached, 1)
        // The plain button, with the line off the cross, would have been ignored.
        let (plain, _) = try askingRoute()
        drift(plain)
        plain.answer(.yes)
        XCTAssertEqual(plain.guide.edgesReached, 0, "the old path ignores a tap off the cross")
    }

    func testNoRejectsTheCapturedEdgeAndTheRunCarriesOn() throws {
        let (route, question) = try askingRoute()
        drift(route)
        route.seconds += 0.1
        let step = try XCTUnwrap(
            route.guide.answerEdgeQuestion(
                question, .no, route.reading(ScriptedRoute.Frame(still: true))))
        XCTAssertEqual(step.instruction, .notAnEdge)
        XCTAssertEqual(route.guide.edgesReached, 0)
        XCTAssertFalse(route.guide.isFinished)
        route.feed(ScriptedRoute.Frame(), move: left, times: 5)
        XCTAssertFalse(route.guide.isFinished, "it carries on")
    }

    func testAnAnswerAfterTheRunEndedChangesNothing() throws {
        let (route, question) = try askingRoute()
        route.guide.endNow()
        route.seconds += 0.1
        let edges = route.guide.edgesReached
        XCTAssertNil(
            route.guide.answerEdgeQuestion(
                question, .yes, route.reading(ScriptedRoute.Frame(still: true))))
        XCTAssertEqual(route.guide.edgesReached, edges)
    }

    // MARK: The engine: answers are queued, none dropped

    func testAnswersSentWhileTheQueueIsBusyAreAllAppliedInOrder() {
        let engine = ScanEngine()
        engine.setGuideDryRun(true)
        // The analysis queue is busy when the taps arrive.
        engine.analysisQueue.async { Thread.sleep(forTimeInterval: 0.3) }
        engine.answerEdge(.yes, questionID: 3)
        engine.answerEdge(.no, questionID: 4)
        engine.answerEdge(.yes, questionID: 5)
        var log: [ScanEngine.EdgeAnswerRecord] = []
        engine.analysisQueue.sync { log = engine.edgeAnswerLog }
        XCTAssertEqual(log.map(\.questionID), [3, 4, 5], "in order, none dropped")
        XCTAssertEqual(log.map(\.feedback), [.yes, .no, .yes])
        // There was no such question on screen: each is late, and none changed anything.
        XCTAssertTrue(log.allSatisfy { $0.outcome == .late })
    }

    // MARK: The card

    private func input(
        _ seconds: Double, _ instruction: GuideInstruction, question: Int? = nil
    ) -> GuidedScanInput {
        GuidedScanInput(
            seconds: seconds, instruction: instruction, arrow: CGPoint(x: -1, y: 0),
            questionID: question, column: 1, lastColumn: false, slipHeightFields: nil,
            sideInsetFields: nil, captureCount: 0, isFinished: false)
    }

    func testTheCardChangesTheMomentYouTapAndNeverStaysOnAnAnsweredQuestion() {
        var presenter = GuidedScanPresenter()
        _ = presenter.present(input(0, .move(toward: CGPoint(x: 0.5, y: 0))))
        let asked = presenter.present(input(1, .edgeDetected, question: 7))
        XCTAssertEqual(asked.card, .question)
        XCTAssertEqual(asked.questionID, 7)

        let yes = presenter.answered(yes: true, questionID: 7, at: 1.1)
        XCTAssertEqual(yes.card, .edgeFound)
        XCTAssertEqual(yes.haptic, .success)
        XCTAssertNil(yes.questionID)
        // A reading that still carries the answered question does not bring the card back.
        let stale = presenter.present(input(1.2, .edgeDetected, question: 7))
        XCTAssertNotEqual(stale.card, .question)
        // A newer question does.
        XCTAssertEqual(presenter.present(input(5, .edgeDetected, question: 8)).card, .question)
    }

    func testNoGoesBackToTheCardBeforeTheQuestion() {
        var presenter = GuidedScanPresenter()
        let turn = presenter.present(input(0, .move(toward: CGPoint(x: 0.5, y: 0))))
        _ = presenter.present(input(1, .edgeDetected, question: 2))
        let no = presenter.answered(yes: false, questionID: 2, at: 1.1)
        XCTAssertEqual(no.card, turn.card)
        XCTAssertNil(no.questionID)
    }

    // MARK: End run

    func testTheMenuOffersWhatIsValid() {
        XCTAssertEqual(
            EndRunMenu.items(columnInProgress: true, endingAfterColumn: false),
            [.endNow, .endAfterColumn, .discard, .keepScanning])
        XCTAssertEqual(
            EndRunMenu.items(columnInProgress: false, endingAfterColumn: false),
            [.endNow, .discard, .keepScanning])
        XCTAssertEqual(
            EndRunMenu.items(columnInProgress: true, endingAfterColumn: true),
            [.undo, .endNow, .discard, .keepScanning])
        XCTAssertEqual(EndRunMenu.awayItems, [.endNow, .discard, .keepScanning])
        XCTAssertEqual(EndRunMenu.Item.discard.title, "Stop and discard")
        XCTAssertNil(EndRunMenu.Item.discard.action, "the page asks first; nothing ends here")
        XCTAssertEqual(EndRunMenu.Item.endNow.action, .now)
        XCTAssertEqual(EndRunMenu.Item.endAfterColumn.action, .afterColumn)
        XCTAssertEqual(EndRunMenu.Item.undo.action, .cancel)
        XCTAssertNil(EndRunMenu.Item.keepScanning.action)
        XCTAssertEqual(EndRunMenu.label(endingAfterColumn: true), "Ending after this column")
        XCTAssertEqual(EndRunMenu.label(endingAfterColumn: false), "End run")
    }

    func testEndNowFinishesTheRunAndItSavesAsASweepForTheResults() throws {
        let route = ScriptedRoute(fullCoverSlip: true, asksEdges: true)
        route.feed(move: left, times: 10)
        route.guide.endNow()
        route.feed(ScriptedRoute.Frame(), times: 2)
        XCTAssertTrue(route.guide.isFinished)
        XCTAssertEqual(route.guide.finishReason, .endedByHelper)
        XCTAssertEqual(route.last.instruction, .finished)

        // The saved run opens the results screen's result.
        var record = GuideRunRecord.previewForTests
        record.finishReason = try XCTUnwrap(route.guide.finishReason)
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "end-now-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let details = SampleDetails(
            sampleID: "A", location: "B", field: 1, moisture: .drained, gramsOfSoil: 10,
            millilitresScanned: nil, recordedAt: Date(timeIntervalSince1970: 1_793_176_205))
        let name = try GuidedScanSaver.save(
            details: details, record: record, movementCSV: nil, in: directory)
        let sweep = try XCTUnwrap(SweepLibrary.sweeps(in: directory).first { $0.name == name })
        XCTAssertNoThrow(try SoilResult(sweep: sweep))
    }
}

/// A line fixture, as the line-rule tests build it.
private enum EdgeLineFixtures {
    static func line(_ offset: Double, residual: Double?) -> EdgeLine {
        EdgeLine(
            strength: 30, coverage: 1, longestRun: 8, angleDegrees: 0, offsetFields: offset,
            sign: 1, slideResidualFields: residual, path: [], isCandidate: true, beforeEnergy: nil,
            beyondEnergy: nil)
    }
}
