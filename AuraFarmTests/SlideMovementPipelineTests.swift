#if DEBUG
    import XCTest

    @testable import AuraFarm

    final class SlideMovementPipelineTests: XCTestCase {
        private let size = 256

        private func frame(shiftedBy dx: Int) -> CVPixelBuffer {
            let texture = SyntheticFrame.smoothNoise(size: size)
            return SyntheticFrame.make(width: size, height: size) { [size] x, y in
                UInt8(texture[y * size + min(max(x - dx, 0), size - 1)])
            }
        }

        /// The whole frame, so these synthetic frames (no eyepiece ring) behave as before.
        private func wholeFramePipeline(hopFraction: Double = 0.3) -> SlideMovementPipeline {
            let pipeline = SlideMovementPipeline(
                thresholds: HopOdometerThresholds(hopFraction: hopFraction))
            pipeline.fieldMode = .wholeFrame
            return pipeline
        }

        /// A frame with a static, off-centre dark ring: the field is a disc centred left of the
        /// middle that runs off the left edge, so the dark part is a crescent on the right. The
        /// texture moves only inside the field. Kept above the dark threshold.
        private func crescentFrame(shiftedBy dx: Int) -> CVPixelBuffer {
            let texture = SyntheticFrame.smoothNoise(size: size)
            return SyntheticFrame.make(width: size, height: size) { [size] x, y in
                guard hypot(Double(x) - 100, Double(y) - 128) <= 110 else { return 2 }
                return UInt8(70 + texture[y * size + min(max(x - dx, 0), size - 1)] * 0.5)
            }
        }

        func testTrackingWaitsForTheFieldToBeConfirmedAndAnAdjustmentSticks() throws {
            let pipeline = SlideMovementPipeline(thresholds: HopOdometerThresholds(hopFraction: 0.1))
            pipeline.requiresReview = true
            pipeline.fieldMode = .brightRegion
            _ = pipeline.process(crescentFrame(shiftedBy: 0), seconds: 0, measureAgreement: false)
            XCTAssertTrue(pipeline.isAwaitingReview)

            pipeline.adjustField(to: FieldCircle(centre: CGPoint(x: 100, y: 128), radius: 80))
            for index in 1...3 {
                let step = try XCTUnwrap(
                    pipeline.process(
                        crescentFrame(shiftedBy: index * 30), seconds: Double(index) * 0.1,
                        measureAgreement: false))
                XCTAssertNil(step.shake, "no tracking while the field is under review")
                XCTAssertTrue(step.awaitingReview)
            }
            guard case .ready(let mask) = pipeline.fieldState else { return XCTFail("no mask") }
            XCTAssertLessThan(try XCTUnwrap(mask.registrationRect).maxX, 180)

            pipeline.confirmField()
            XCTAssertFalse(pipeline.isAwaitingReview)
            _ = pipeline.process(crescentFrame(shiftedBy: 0), seconds: 1, measureAgreement: false)
            let step = try XCTUnwrap(
                pipeline.process(crescentFrame(shiftedBy: 20), seconds: 1.1, measureAgreement: false))
            XCTAssertFalse(step.awaitingReview)
            XCTAssertNotNil(step.anchorOffset)
        }

        func testAutoHopsAtAQuarterOfTheBoxOnARealisticRoundField() throws {
            // 1280 x 720 frames, a static round field of radius 285 px about the middle, and
            // texture that moves 30 px to the right on every frame.
            let width = 1280
            let height = 720
            let texture = SyntheticFrame.smoothNoise(size: width)
            func ringFrame(shiftedBy dx: Int) -> CVPixelBuffer {
                SyntheticFrame.make(width: width, height: height) { x, y in
                    guard hypot(Double(x) - 640, Double(y) - 360) <= 285 else { return 2 }
                    return UInt8(70 + texture[y * width + min(max(x - dx, 0), width - 1)] * 0.5)
                }
            }
            let pipeline = SlideMovementPipeline()
            let learningFrames = FieldMaskThresholds().framesToLearn
            for index in 0..<learningFrames {
                _ = pipeline.process(
                    ringFrame(shiftedBy: 0), seconds: Double(index) * 0.1, measureAgreement: false)
            }
            guard case .ready(let mask) = pipeline.fieldState else {
                return XCTFail("expected a learned field, got \(pipeline.fieldState)")
            }
            XCTAssertEqual(mask.openShare, .pi * 285 * 285 / Double(width * height), accuracy: 0.03)

            var last: SlideMovementStep?
            var hopFrames: [Int] = []
            for index in 0...10 {
                let seconds = Double(learningFrames + index) * 0.1
                let step = try XCTUnwrap(
                    pipeline.process(
                        ringFrame(shiftedBy: index * 30), seconds: seconds, measureAgreement: false))
                if step.event == .hop { hopFrames.append(index) }
                XCTAssertFalse(step.isLost, "lost at frame \(index)")
                last = step
            }
            let final = try XCTUnwrap(last)
            // The box is the square inside the field: about 340 to 380 px, hopping at a quarter.
            XCTAssertEqual(final.boxSide, 355, accuracy: 30)
            XCTAssertEqual(final.hopLimit, final.boxSide * 0.25, accuracy: 0.001)
            XCTAssertEqual(final.gaps, 0)
            XCTAssertEqual(final.position.x, 300, accuracy: 15)
            XCTAssertEqual(final.position.y, 0, accuracy: 6)
            XCTAssertEqual(hopFrames, [3, 6, 9], "a hop about every 88 px, so every third frame")
            XCTAssertEqual(final.positionFields.x, 300 / final.boxSide, accuracy: 0.05)
        }

        func testBrightRegionLearnsFromOneFrame() throws {
            let pipeline = SlideMovementPipeline()
            pipeline.fieldMode = .brightRegion
            XCTAssertTrue(pipeline.isLearning)
            let step = try XCTUnwrap(
                pipeline.process(crescentFrame(shiftedBy: 0), seconds: 0, measureAgreement: false))
            guard case .ready(let mask) = pipeline.fieldState else {
                return XCTFail("expected a mask after one frame, got \(pipeline.fieldState)")
            }
            let rect = try XCTUnwrap(mask.registrationRect)
            XCTAssertLessThanOrEqual(rect.maxX, 210)
            XCTAssertEqual(step.fieldRegionName, "bright-region-learned")
        }

        func testAutoLearnsTheCrescentThenTracksAndNeverHopsWhileLearning() throws {
            let pipeline = SlideMovementPipeline(thresholds: HopOdometerThresholds(hopFraction: 0.1))
            let framesToLearn = FieldMaskThresholds().framesToLearn
            for index in 0..<framesToLearn {
                // The picture is moving while the mask is learned: still no hops, no lost.
                let step = try XCTUnwrap(
                    pipeline.process(
                        crescentFrame(shiftedBy: index * 30), seconds: Double(index) * 0.1,
                        measureAgreement: false))
                XCTAssertEqual(step.event, .none)
                XCTAssertEqual(step.hops, 0)
                XCTAssertFalse(step.isLost)
                XCTAssertNil(step.shake)
                if index < framesToLearn - 1 { XCTAssertNil(step.registrationRect) }
            }
            guard case .ready(let mask) = pipeline.fieldState else {
                return XCTFail("expected a learned mask, got \(pipeline.fieldState)")
            }
            let rect = try XCTUnwrap(mask.registrationRect)
            XCTAssertLessThanOrEqual(rect.maxX, 210, "stays inside the field, off the dark side")

            var seconds = Double(framesToLearn) * 0.1
            // The first frame after learning anchors; the next one moves 40 px.
            _ = pipeline.process(crescentFrame(shiftedBy: 0), seconds: seconds, measureAgreement: false)
            seconds += 0.1
            let step = try XCTUnwrap(
                pipeline.process(
                    crescentFrame(shiftedBy: 40), seconds: seconds, measureAgreement: false))
            XCTAssertEqual(step.event, .hop)
            XCTAssertEqual(abs(step.position.x), 40, accuracy: 5)
            XCTAssertEqual(step.registrationRect, rect)
            XCTAssertEqual(step.fieldRegionName, "auto-learned")
        }

        func testWholeFrameCannotSeeThroughTheRing() throws {
            let whole = wholeFramePipeline(hopFraction: 0.1)
            _ = whole.process(crescentFrame(shiftedBy: 0), seconds: 0, measureAgreement: false)
            let blind = try XCTUnwrap(
                whole.process(crescentFrame(shiftedBy: 40), seconds: 0.1, measureAgreement: false))
            XCTAssertNil(blind.registrationRect)
            XCTAssertEqual(blind.fieldRegionName, "whole-frame")
            XCTAssertNil(blind.fieldState)
        }

        func testRedetectingStartsLearningAgainAndResetKeepsALearnedMask() throws {
            let pipeline = SlideMovementPipeline(thresholds: HopOdometerThresholds(hopFraction: 0.1))
            for index in 0..<FieldMaskThresholds().framesToLearn {
                _ = pipeline.process(
                    crescentFrame(shiftedBy: 0), seconds: Double(index) * 0.1,
                    measureAgreement: false)
            }
            XCTAssertFalse(pipeline.isLearning)
            pipeline.resetPosition()
            XCTAssertFalse(pipeline.isLearning, "a learned mask is kept by Reset position")
            pipeline.redetectField()
            XCTAssertTrue(pipeline.isLearning)
        }

        func testAMostlyDarkViewIsNotTrustedAndFallsBackToTheCentreSquare() throws {
            let pipeline = SlideMovementPipeline()
            // Only a small bright patch is open: under the share a mask needs to be trusted.
            let dark = SyntheticFrame.make(width: size, height: size) { x, y in
                (100..<170).contains(x) && (100..<170).contains(y) ? 180 : 3
            }
            var last: SlideMovementStep?
            for index in 0...FieldMaskThresholds().framesToLearn {
                last = pipeline.process(dark, seconds: Double(index) * 0.1, measureAgreement: false)
            }
            guard case .untrusted = pipeline.fieldState else {
                return XCTFail("expected untrusted, got \(pipeline.fieldState)")
            }
            XCTAssertEqual(last?.fieldRegionName, "auto-untrusted")
            XCTAssertEqual(
                last?.registrationRect,
                EyepieceField.centreSquare(frameSize: CGSize(width: size, height: size)))
        }

        func testTheStepCarriesItsCost() throws {
            let pipeline = wholeFramePipeline()
            let step = try XCTUnwrap(
                pipeline.process(frame(shiftedBy: 0), seconds: 0, measureAgreement: false))
            XCTAssertGreaterThan(step.analysisMilliseconds, 0)
            XCTAssertEqual(step.analyzedFps, 0, "one frame is no rate yet")
        }

        func testTheFirstFrameOnlyAnchors() throws {
            let pipeline = wholeFramePipeline(hopFraction: 0.1)
            let step = try XCTUnwrap(
                pipeline.process(frame(shiftedBy: 0), seconds: 0, measureAgreement: false))
            XCTAssertEqual(step.event, .none)
            XCTAssertNil(step.anchorOffset)
            XCTAssertFalse(step.isLost)
            XCTAssertEqual(step.position, .zero)
        }

        func testAHopIsCountedAndReanchors() throws {
            let pipeline = wholeFramePipeline(hopFraction: 0.1)
            _ = pipeline.process(frame(shiftedBy: 0), seconds: 0, measureAgreement: true)
            // Short side 256 and a hop at 0.1 of it: 26 px. A 40 px move is a hop and is trusted (limit 102).
            let hop = try XCTUnwrap(
                pipeline.process(frame(shiftedBy: 40), seconds: 0.1, measureAgreement: true))
            XCTAssertEqual(hop.event, .hop)
            XCTAssertEqual(hop.hops, 1)
            XCTAssertEqual(hop.position.x, 40, accuracy: 4)
            XCTAssertNotNil(hop.hopAgreement)
            // The hop re-anchored on that frame, so the same frame again reads no travel.
            let still = try XCTUnwrap(
                pipeline.process(frame(shiftedBy: 40), seconds: 0.2, measureAgreement: true))
            XCTAssertEqual(still.event, .none)
            XCTAssertEqual(still.position.x, 40, accuracy: 4)
        }

        func testAgreementIsRationed() throws {
            let pipeline = wholeFramePipeline(hopFraction: 0.1)
            _ = pipeline.process(frame(shiftedBy: 0), seconds: 0, measureAgreement: true)
            let first = try XCTUnwrap(
                pipeline.process(frame(shiftedBy: 40), seconds: 0.1, measureAgreement: true))
            let second = try XCTUnwrap(
                pipeline.process(frame(shiftedBy: 80), seconds: 0.2, measureAgreement: true))
            XCTAssertNotNil(first.hopAgreement)
            XCTAssertEqual(second.event, .hop)
            XCTAssertNil(second.hopAgreement, "within a second of the last measurement")
        }

        func testResetPositionForgetsTheAnchor() throws {
            let pipeline = wholeFramePipeline(hopFraction: 0.1)
            _ = pipeline.process(frame(shiftedBy: 0), seconds: 0, measureAgreement: false)
            _ = pipeline.process(frame(shiftedBy: 40), seconds: 0.1, measureAgreement: false)
            pipeline.resetPosition()
            let step = try XCTUnwrap(
                pipeline.process(frame(shiftedBy: 40), seconds: 0.2, measureAgreement: false))
            XCTAssertEqual(step.position, .zero)
            XCTAssertEqual(step.hops, 0)
        }
    }
#endif
