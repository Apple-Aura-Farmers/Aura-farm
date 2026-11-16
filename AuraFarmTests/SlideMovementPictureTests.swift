#if DEBUG
    import XCTest

    @testable import AuraFarm

    /// Phase 2: recovering the position after a stretch with nothing to track, and the picture
    /// check against the Mark start picture. Real Vision on synthetic frames throughout; the
    /// anchor reading seam is not used.
    final class SlideMovementPictureTests: XCTestCase {
        private let width = 1280
        private let height = 720
        private lazy var texture = SyntheticFrame.smoothNoise(size: width)
        private var seconds = 10.0

        private var cache: [Int: CVPixelBuffer] = [:]

        /// Frames are never changed by the pipeline, so one per shift is made and reused.
        private func ringFrame(shiftedBy dx: Int) -> CVPixelBuffer {
            if let cached = cache[dx] { return cached }
            let frame = makeRingFrame(shiftedBy: dx)
            cache[dx] = frame
            return frame
        }

        private func makeRingFrame(shiftedBy dx: Int) -> CVPixelBuffer {
            SyntheticFrame.make(width: width, height: height) { [self] x, y in
                guard hypot(Double(x) - 640, Double(y) - 360) <= 285 else { return 2 }
                return UInt8(70 + texture[y * width + min(max(x - dx, 0), width - 1)] * 0.5)
            }
        }

        private func blankFrame() -> CVPixelBuffer {
            SyntheticFrame.make(width: width, height: height) { x, y in
                hypot(Double(x) - 640, Double(y) - 360) <= 285 ? 90 : 2
            }
        }

        private func learned() -> SlideMovementPipeline {
            let pipeline = SlideMovementPipeline()
            for index in 0..<FieldMaskThresholds().framesToLearn {
                _ = pipeline.process(
                    ringFrame(shiftedBy: 0), seconds: Double(index) * 0.1, measureAgreement: false)
            }
            return pipeline
        }

        @discardableResult
        private func feed(_ pipeline: SlideMovementPipeline, _ frame: CVPixelBuffer) throws
            -> SlideMovementStep
        {
            seconds += 0.1
            return try XCTUnwrap(pipeline.process(frame, seconds: seconds, measureAgreement: false))
        }

        /// Anchors, holds still a few frames, then goes blank for a while.
        private func intoTheBlank(_ pipeline: SlideMovementPipeline) throws -> SlideMovementStep {
            var step = try feed(pipeline, ringFrame(shiftedBy: 0))
            for _ in 0..<3 { step = try feed(pipeline, ringFrame(shiftedBy: 0)) }
            for _ in 0..<8 { step = try feed(pipeline, blankFrame()) }
            XCTAssertFalse(step.hasDetail)
            return step
        }

        // MARK: Blank returns

        func testReturningToTheSamePictureMovedAFifthOfTheBoxRecoversThePosition() throws {
            let pipeline = learned()
            let before = try intoTheBlank(pipeline)
            let shift = Int(before.boxSide * 0.2)
            var events: [String] = []
            var readings: [String] = []
            var step = before
            for _ in 0..<10 {
                step = try feed(pipeline, ringFrame(shiftedBy: shift))
                events.append(step.blankReturnEvent)
                readings.append(step.reading)
                XCTAssertFalse(step.isLost)
            }
            print("blank return matched: shift \(shift) position \(step.position) readings \(readings)")
            XCTAssertEqual(events.filter { $0 == "matched" }.count, 1)
            XCTAssertTrue(readings.contains("matching"))
            XCTAssertEqual(step.blankReturnsMatched, 1)
            XCTAssertEqual(step.blankReturnsUnmatched, 0)
            XCTAssertEqual(
                step.position.x, Double(shift), accuracy: 12, "the move over the blank is not lost")
            XCTAssertEqual(step.position.y, 0, accuracy: 8)
        }

        func testThePositionStaysWhereItWasWhileMatchingIsPending() throws {
            let pipeline = learned()
            let before = try intoTheBlank(pipeline)
            let shift = Int(before.boxSide * 0.2)
            var pendingPositions: [CGPoint] = []
            for _ in 0..<10 {
                let step = try feed(pipeline, ringFrame(shiftedBy: shift))
                if step.reading == "matching" { pendingPositions.append(step.position) }
            }
            XCTAssertFalse(pendingPositions.isEmpty)
            XCTAssertTrue(pendingPositions.allSatisfy { $0 == before.position })
        }

        func testComingBackTooFarFallsBackToTheLastKnownPosition() throws {
            let pipeline = learned()
            let before = try intoTheBlank(pipeline)
            // 0.6 of the box is past the 0.4 limit for a trusted match.
            let shift = Int(before.boxSide * 0.6)
            var step = before
            var decided = ""
            for _ in 0..<16 {
                step = try feed(pipeline, ringFrame(shiftedBy: shift))
                if !step.blankReturnEvent.isEmpty { decided = step.blankReturnEvent }
            }
            XCTAssertEqual(decided, "unmatched")
            XCTAssertEqual(step.blankReturnsUnmatched, 1)
            XCTAssertEqual(step.blankReturnsMatched, 0)
            XCTAssertEqual(step.position.x, before.position.x, accuracy: 12, "falls back, no loss claimed")
            XCTAssertFalse(step.isLost)
        }

        func testLosingDetailAgainWhileMatchingAbandonsTheCheckAndKeepsTheAnchor() throws {
            let pipeline = learned()
            let before = try intoTheBlank(pipeline)
            let shift = Int(before.boxSide * 0.2)
            // Detail comes back (3 readings) and matching starts (2 readings, one short of
            // deciding), then the glass goes blank again.
            for _ in 0..<4 { try feed(pipeline, ringFrame(shiftedBy: shift)) }
            for _ in 0..<6 { try feed(pipeline, blankFrame()) }
            var step = try feed(pipeline, blankFrame())
            XCTAssertFalse(step.hasDetail)
            XCTAssertEqual(step.blankReturnsMatched + step.blankReturnsUnmatched, 0)
            // The same anchor still recovers the position on the next return.
            for _ in 0..<10 { step = try feed(pipeline, ringFrame(shiftedBy: shift)) }
            XCTAssertEqual(step.blankReturnsMatched, 1)
            XCTAssertEqual(step.position.x, Double(shift), accuracy: 12)
        }

        func testResetPositionClearsTheCountersAndTheCheck() throws {
            let pipeline = learned()
            let before = try intoTheBlank(pipeline)
            let shift = Int(before.boxSide * 0.2)
            for _ in 0..<10 { try feed(pipeline, ringFrame(shiftedBy: shift)) }
            XCTAssertEqual(pipeline.blankReturnsMatched, 1)
            pipeline.resetPosition()
            XCTAssertEqual(pipeline.blankReturnsMatched, 0)
            XCTAssertEqual(pipeline.blankReturnsUnmatched, 0)
        }

        // MARK: Picture check

        func testThePictureCheckMeasuresTheTrueChangeSinceMarkStart() throws {
            let pipeline = learned()
            try feed(pipeline, ringFrame(shiftedBy: 0))
            pipeline.setStartPicture()
            var step = try feed(pipeline, ringFrame(shiftedBy: 0))
            XCTAssertEqual(step.pictureCheck, "matching")
            var states: [String] = []
            for index in 1...8 {
                step = try feed(pipeline, ringFrame(shiftedBy: index * 15))
                states.append(step.pictureCheck)
            }
            print(
                "picture check: states \(states) match \(String(describing: step.startMatch)) true \(String(describing: step.trueOffStartFields)) error \(String(describing: step.trackerErrorFields))"
            )
            XCTAssertEqual(step.pictureCheck, "confirmed")
            let match = try XCTUnwrap(step.startMatch)
            XCTAssertEqual(match.x, 120, accuracy: 6)
            XCTAssertEqual(match.y, 0, accuracy: 6)
            XCTAssertEqual(try XCTUnwrap(step.trueOffStartFields), 120 / step.boxSide, accuracy: 0.03)
            XCTAssertEqual(try XCTUnwrap(step.trackerErrorFields), 0, accuracy: 0.05)
        }

        func testOutOfRangeAndBackInRange() throws {
            let pipeline = learned()
            try feed(pipeline, ringFrame(shiftedBy: 0))
            pipeline.setStartPicture()
            try feed(pipeline, ringFrame(shiftedBy: 0))
            var step = try feed(pipeline, ringFrame(shiftedBy: 0))
            // Go well beyond 0.4 of the box (about 143 px) in steps the tracker can follow.
            for index in 1...12 { step = try feed(pipeline, ringFrame(shiftedBy: index * 25)) }
            XCTAssertEqual(step.pictureCheck, "out_of_range")
            XCTAssertNil(step.startMatch)
            // And back to within range of the start.
            for shift in stride(from: 275, through: 0, by: -25) {
                step = try feed(pipeline, ringFrame(shiftedBy: shift))
            }
            for _ in 0..<6 { step = try feed(pipeline, ringFrame(shiftedBy: 0)) }
            XCTAssertEqual(step.pictureCheck, "confirmed")
            XCTAssertEqual(try XCTUnwrap(step.startMatch).x, 0, accuracy: 8)
        }

        func testNoStartPictureMeansNothing() throws {
            let pipeline = learned()
            let step = try feed(pipeline, ringFrame(shiftedBy: 0))
            XCTAssertEqual(step.pictureCheck, "none")
            XCTAssertNil(step.startMatch)
            XCTAssertNil(step.trueOffStartFields)
            XCTAssertNil(step.trackerErrorFields)
        }

        func testResetPositionAndAChangedBoxClearTheStartPicture() throws {
            let pipeline = learned()
            try feed(pipeline, ringFrame(shiftedBy: 0))
            pipeline.setStartPicture()
            var step = try feed(pipeline, ringFrame(shiftedBy: 0))
            XCTAssertNotEqual(step.pictureCheck, "none")
            pipeline.resetPosition()
            step = try feed(pipeline, ringFrame(shiftedBy: 0))
            XCTAssertEqual(step.pictureCheck, "none")

            // The box changes with the mode.
            try feed(pipeline, ringFrame(shiftedBy: 0))
            pipeline.setStartPicture()
            step = try feed(pipeline, ringFrame(shiftedBy: 0))
            XCTAssertNotEqual(step.pictureCheck, "none")
            pipeline.fieldMode = .centreSquare
            step = try feed(pipeline, ringFrame(shiftedBy: 0))
            XCTAssertEqual(step.pictureCheck, "none")
        }

        // MARK: Dry run and cost

        func testTheDryRunFeedsTheGuideFromAStep() throws {
            let pipeline = learned()
            let step = try feed(pipeline, ringFrame(shiftedBy: 0))
            let dryRun = GuideDryRun()
            let result = dryRun.update(step: step, indicators: MovementIndicators(), seconds: 1)
            XCTAssertEqual(result.fields.viewClass, "sample")
            XCTAssertEqual(result.fields.instruction, "travel", "sample found: head for the left edge")
            XCTAssertEqual(result.fields.state, "find left edge")
            XCTAssertNil(result.fields.targetDx)
            dryRun.reset()
            XCTAssertEqual(dryRun.captureCount, 0)
        }

        /// Prints the analysis cost per tracked frame without and with a start picture
        /// active. A Simulator's CPU: a comparison, not a budget.
        func testAnalysisCostWithAndWithoutAStartPicture() throws {
            func average(withStartPicture: Bool) throws -> Double {
                let pipeline = learned()
                try feed(pipeline, ringFrame(shiftedBy: 0))
                if withStartPicture { pipeline.setStartPicture() }
                var total = 0.0
                var count = 0.0
                for index in 0..<12 {
                    let step = try feed(pipeline, ringFrame(shiftedBy: index * 10))
                    if index >= 2 {
                        total += step.analysisMilliseconds
                        count += 1
                    }
                }
                return total / count
            }
            let without = try average(withStartPicture: false)
            let with = try average(withStartPicture: true)
            print(
                String(
                    format: "analysis ms per tracked frame: without start picture %.1f, with %.1f", without,
                    with))
            XCTAssertGreaterThan(without, 0)
            XCTAssertGreaterThan(with, 0)
        }

        // MARK: BoxRegistration overload

        func testTheStoredPictureOverloadAgreesWithTheBufferFunction() throws {
            let registration = BoxRegistration()
            let box = CGRect(x: 461, y: 181, width: 358, height: 358)
            let held = ringFrame(shiftedBy: 0)
            let current = ringFrame(shiftedBy: 37)
            let context = CIContext(options: [.useSoftwareRenderer: false])
            let stored = try XCTUnwrap(registration.copy(of: held, box: box, context: context))
            XCTAssertEqual(stored.width, 358)
            let direct = try XCTUnwrap(registration.offset(from: held, to: current, box: box))
            let viaStored = try XCTUnwrap(registration.offset(fromStored: stored, to: current, box: box))
            XCTAssertEqual(viaStored.x, direct.x, accuracy: 2)
            XCTAssertEqual(viaStored.y, direct.y, accuracy: 2)
            XCTAssertEqual(viaStored.x, 37, accuracy: 4)
            // A stored picture of another size is refused.
            XCTAssertNil(
                registration.offset(
                    fromStored: stored, to: current, box: CGRect(x: 461, y: 181, width: 300, height: 300)))
        }
    }
#endif
