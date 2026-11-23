import XCTest

@testable import AuraFarm

final class StageEdgeAnswerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1000)

    func testEachQuestionIsAnsweredOnceAfterItHasStoodAMoment() {
        var answer = StageEdgeAnswer()
        XCTAssertNil(answer.update(questionID: 3, now: start))
        XCTAssertNil(answer.update(questionID: 3, now: start + 0.9))
        XCTAssertEqual(answer.update(questionID: 3, now: start + 1), 3)
        XCTAssertNil(answer.update(questionID: 3, now: start + 5), "answered already")
        XCTAssertNil(answer.update(questionID: 4, now: start + 5), "a new one waits its moment")
        XCTAssertEqual(answer.update(questionID: 4, now: start + 6), 4)
    }

    func testAQuestionThatGoesAwayIsNotAnsweredAndNoIdIsNone() {
        var answer = StageEdgeAnswer()
        XCTAssertNil(answer.update(questionID: 1, now: start))
        answer.questionGone()
        XCTAssertNil(answer.update(questionID: 1, now: start + 2), "waits again")
        XCTAssertNil(answer.update(questionID: nil, now: start + 9))
    }

    func testTheSameIdInTheNextRunIsAnsweredAgain() {
        var answer = StageEdgeAnswer()
        _ = answer.update(questionID: 1, now: start)
        XCTAssertEqual(answer.update(questionID: 1, now: start + 1), 1)
        answer.questionGone()
        _ = answer.update(questionID: 1, now: start + 20)
        XCTAssertEqual(answer.update(questionID: 1, now: start + 21), 1)
    }
}
