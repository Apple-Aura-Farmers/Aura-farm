import XCTest

@testable import AuraFarm

/// `FieldRegionLearner` on its own, on synthetic eyepiece frames (a bright disc on black).
final class FieldRegionLearnerTests: XCTestCase {
    private let frameSize = CGSize(width: 1280, height: 720)
    private let framesToLearn = FieldMaskThresholds().framesToLearn
    private lazy var disc: CVPixelBuffer = SyntheticFrame.make(width: 1280, height: 720) { x, y in
        hypot(Double(x) - 640, Double(y) - 360) <= 285 ? 120 : 2
    }

    private func learned(requiresReview: Bool = false) -> FieldRegionLearner {
        let learner = FieldRegionLearner()
        learner.requiresReview = requiresReview
        for _ in 0..<framesToLearn { _ = learner.process(disc, frameSize: frameSize) }
        return learner
    }

    func testWholeFrameAndCentreSquareGiveTheExpectedRects() {
        let learner = FieldRegionLearner()
        learner.mode = .wholeFrame
        var update = learner.process(disc, frameSize: frameSize)
        XCTAssertNil(learner.registrationRect)
        XCTAssertFalse(update.spentLearning)

        learner.mode = .centreSquare
        update = learner.process(disc, frameSize: frameSize)
        XCTAssertEqual(learner.registrationRect, EyepieceField.centreSquare(frameSize: frameSize))
        XCTAssertTrue(update.regionChanged, "the box moved")
        XCTAssertFalse(learner.process(disc, frameSize: frameSize).regionChanged)
    }

    func testAutoLearningCompletesOnADisc() throws {
        let learner = FieldRegionLearner()
        XCTAssertTrue(learner.isLearning)
        for index in 0..<framesToLearn {
            let update = learner.process(disc, frameSize: frameSize)
            XCTAssertTrue(update.spentLearning)
            XCTAssertEqual(update.regionChanged, index == framesToLearn - 1)
        }
        guard case .ready = learner.state else { return XCTFail("got \(learner.state)") }
        let rect = try XCTUnwrap(learner.registrationRect)
        XCTAssertTrue(CGRect(x: 355, y: 75, width: 570, height: 570).contains(rect))
        let next = learner.process(disc, frameSize: frameSize)
        XCTAssertFalse(next.spentLearning)
        XCTAssertFalse(next.regionChanged)
    }

    func testReviewHoldsFramesUntilConfirmed() {
        let learner = learned(requiresReview: true)
        XCTAssertTrue(learner.isAwaitingReview)
        XCTAssertTrue(learner.process(disc, frameSize: frameSize).spentLearning)
        learner.confirm()
        XCTAssertFalse(learner.isAwaitingReview)
        let update = learner.process(disc, frameSize: frameSize)
        XCTAssertFalse(update.spentLearning)
        XCTAssertTrue(update.regionChanged)
        XCTAssertFalse(learner.process(disc, frameSize: frameSize).regionChanged)
    }

    func testAdjustAndRedetectReportARegionChange() {
        let learner = learned()
        _ = learner.process(disc, frameSize: frameSize)

        learner.adjust(to: FieldCircle(centre: CGPoint(x: 640, y: 360), radius: 150))
        var update = learner.process(disc, frameSize: frameSize)
        XCTAssertTrue(update.regionChanged)
        XCTAssertFalse(update.spentLearning)
        XCTAssertFalse(learner.process(disc, frameSize: frameSize).regionChanged)

        learner.redetect()
        XCTAssertTrue(learner.isLearning)
        update = learner.process(disc, frameSize: frameSize)
        XCTAssertTrue(update.regionChanged)
        XCTAssertTrue(update.spentLearning)
    }

    func testRestartIfLearningOnlyRestartsWhileLearning() {
        let learner = FieldRegionLearner()
        _ = learner.process(disc, frameSize: frameSize)
        _ = learner.process(disc, frameSize: frameSize)
        guard case .learning(let progress) = learner.state else { return XCTFail("not learning") }
        XCTAssertGreaterThan(progress, 0)
        learner.restartIfLearning()
        XCTAssertEqual(learner.state, .learning(progress: 0))

        let done = learned()
        let state = done.state
        done.restartIfLearning()
        XCTAssertEqual(done.state, state, "a learned mask is kept")
    }
}
