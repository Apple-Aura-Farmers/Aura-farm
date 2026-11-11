import XCTest

@testable import AuraFarm

final class FieldMaskTests: XCTestCase {
    private let gridWidth = 40
    private let gridHeight = 30
    /// A 320x240 frame at the default grid step of 8.
    private let frameSize = CGSize(width: 320, height: 240)

    /// A synthetic luma grid from a function of the cell.
    private func grid(_ value: (Int, Int) -> UInt8) -> [UInt8] {
        (0..<(gridWidth * gridHeight)).map { value($0 % gridWidth, $0 / gridWidth) }
    }

    private func disc(centreX: Double, centreY: Double, radius: Double) -> [UInt8] {
        grid { x, y in hypot(Double(x) - centreX, Double(y) - centreY) <= radius ? 180 : 4 }
    }

    private func learn(
        _ frames: [[UInt8]], thresholds: FieldMaskThresholds = .init(framesToLearn: 4),
        size: CGSize? = nil
    ) -> FieldMask? {
        let size = size ?? frameSize
        var builder = FieldMaskBuilder(
            width: Int(size.width), height: Int(size.height), thresholds: thresholds)
        for frame in frames { builder.add(luma: frame, gridWidth: gridWidth, gridHeight: gridHeight) }
        return builder.result()
    }

    private func same(_ frame: [UInt8], times: Int = 4) -> [[UInt8]] {
        Array(repeating: frame, count: times)
    }

    func testARingAroundABrightDisc() throws {
        let mask = try XCTUnwrap(learn(same(disc(centreX: 20, centreY: 15, radius: 13))))
        XCTAssertTrue(mask.eyepiece[0], "the corner is ring")
        XCTAssertFalse(mask.eyepiece[15 * gridWidth + 20], "the middle is open")
        let rect = try XCTUnwrap(mask.registrationRect)
        XCTAssertGreaterThan(rect.width, 100)
        // Every corner is inside the disc (radius 104 px about the centre), away from its edge.
        for corner in [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY),
        ] {
            XCTAssertLessThan(hypot(corner.x - 160, corner.y - 120), 104 * 0.97)
        }
        XCTAssertTrue(mask.isTrusted)
    }

    func testAnOffCentreFieldCutByTheFrameEdgeKeepsAwayFromTheDarkSide() throws {
        let mask = try XCTUnwrap(learn(same(disc(centreX: 8, centreY: 15, radius: 20))))
        let rect = try XCTUnwrap(mask.registrationRect)
        // The disc reaches x = 28 cells = 224 px; the dark crescent is to the right of that.
        XCTAssertLessThanOrEqual(rect.maxX, 224)
        XCTAssertTrue(mask.eyepiece[15 * gridWidth + 35], "the right side is ring")
        // A centred-circle fit on the open spans (29 cells wide) would give a square of
        // about 2 * 15.5 / sqrt(2) * 0.85 cells = 149 px; the rectangle is bigger.
        XCTAssertGreaterThan(rect.width * rect.height, 149 * 149)
    }

    func testADarkBlobInsideTheFieldIsNotEyepiece() throws {
        let frame = grid { x, y in (15..<22).contains(x) && (10..<18).contains(y) ? 4 : 180 }
        let mask = try XCTUnwrap(learn(same(frame)))
        XCTAssertFalse(mask.eyepiece.contains(true))
        XCTAssertEqual(mask.openShare, 1)
    }

    func testADarkBlobTouchingTheBorderIsEyepiece() throws {
        let frame = grid { x, y in x < 6 && (10..<18).contains(y) ? 4 : 180 }
        let mask = try XCTUnwrap(learn(same(frame)))
        XCTAssertTrue(mask.eyepiece[12 * gridWidth + 2])
        XCTAssertFalse(mask.eyepiece[12 * gridWidth + 10])
    }

    func testAllBrightHasNoEyepieceAndTheRectIsTheFrameLessTheInset() throws {
        let mask = try XCTUnwrap(learn(same(grid { _, _ in 150 })))
        XCTAssertFalse(mask.eyepiece.contains(true))
        let rect = try XCTUnwrap(mask.registrationRect)
        // 6% of 320 is 19.2 and of 240 is 14.4, rounded inwards.
        XCTAssertEqual(rect, CGRect(x: 20, y: 15, width: 280, height: 210))
    }

    func testMostlyDarkIsNotTrusted() throws {
        let frame = grid { x, y in (15..<25).contains(x) && (10..<20).contains(y) ? 180 : 4 }
        let mask = try XCTUnwrap(learn(same(frame)))
        XCTAssertLessThan(mask.openShare, 0.15)
        XCTAssertNil(mask.registrationRect)
        XCTAssertFalse(mask.isTrusted)
    }

    func testACellDarkInOnlyHalfTheFramesIsNotEyepiece() throws {
        let dark = grid { x, y in x < 5 && y < 5 ? 4 : 180 }
        let bright = grid { _, _ in 180 }
        let half = try XCTUnwrap(learn([dark, bright, dark, bright]))
        XCTAssertFalse(half.eyepiece.contains(true))
        let always = try XCTUnwrap(learn(same(dark)))
        XCTAssertTrue(always.eyepiece[0])
    }

    func testTheMaskIsOnlyDecidedAfterEnoughFrames() {
        var builder = FieldMaskBuilder(width: 320, height: 240, thresholds: .init(framesToLearn: 3))
        XCTAssertNil(builder.result())
        XCTAssertEqual(builder.progress, 0)
        builder.add(luma: [UInt8](repeating: 100, count: 10), gridWidth: 5, gridHeight: 2)
        XCTAssertEqual(builder.progress, 0, "a grid of the wrong size is ignored")
        let frame = grid { _, _ in 150 }
        builder.add(luma: frame, gridWidth: gridWidth, gridHeight: gridHeight)
        XCTAssertEqual(builder.progress, 1.0 / 3, accuracy: 0.0001)
        XCTAssertFalse(builder.isComplete)
        builder.add(luma: frame, gridWidth: gridWidth, gridHeight: gridHeight)
        builder.add(luma: frame, gridWidth: gridWidth, gridHeight: gridHeight)
        XCTAssertTrue(builder.isComplete)
        XCTAssertNotNil(builder.result())
    }

    func testTheLargestRectangleOnAHandMadeGrid() throws {
        let rows = [
            [0, 0, 1, 0],
            [1, 1, 1, 1],
            [1, 1, 1, 1],
            [1, 1, 1, 0],
        ]
        let open = rows.flatMap { $0 }.map { $0 == 1 }
        let best = try XCTUnwrap(FieldMaskBuilder.largestRectangle(open: open, width: 4, height: 4))
        XCTAssertEqual([best.x, best.y, best.width, best.height], [0, 1, 3, 3])
        XCTAssertNil(
            FieldMaskBuilder.largestRectangle(
                open: [Bool](repeating: false, count: 6), width: 3, height: 2))
    }

    func testTheRectIsWholePixelsAndInsideTheFrame() throws {
        // A frame that is not a multiple of the grid step.
        let size = CGSize(width: 322, height: 243)
        for frame in [
            disc(centreX: 20, centreY: 15, radius: 13), disc(centreX: 8, centreY: 15, radius: 20),
            grid { _, _ in 150 },
        ] {
            let mask = try XCTUnwrap(learn(same(frame), size: size))
            let rect = try XCTUnwrap(mask.registrationRect)
            XCTAssertTrue(CGRect(origin: .zero, size: size).contains(rect))
            for value in [rect.minX, rect.minY, rect.width, rect.height] {
                XCTAssertEqual(value, value.rounded())
            }
        }
    }

    func testAStrayBrightSpeckInTheRingIsNotTheField() throws {
        // A bright disc, black around it, and a lone bright speck.
        let frame = grid { x, y in
            if x == 1 && y == 1 { return 200 }
            let distance = hypot(Double(x) - 20, Double(y) - 15)
            return distance <= 13 ? 200 : 4
        }
        let mask = try XCTUnwrap(learn(same(frame)))
        XCTAssertFalse(mask.eyepiece[15 * gridWidth + 20], "the disc is field")
        XCTAssertTrue(mask.eyepiece[1 * gridWidth + 1], "the speck is not field")
    }

    func testTheDarkCutIgnoresAnEvenlyLitFrame() {
        let even = [UInt8](repeating: 150, count: 100)
        XCTAssertEqual(FieldMaskBuilder.darkCut(of: even, count: 100, minRatio: 2), 0)
    }

    func testTheLumaGridSamplesTheBufferAndTheTintImageHasTheGridsSize() throws {
        let buffer = SyntheticFrame.make(width: 320, height: 240) { x, _ in x < 160 ? 40 : 200 }
        let sampled = try XCTUnwrap(LumaGrid.sample(of: buffer, step: 8))
        XCTAssertEqual(sampled.width, 40)
        XCTAssertEqual(sampled.height, 30)
        XCTAssertEqual(sampled.luma[0], 40)
        XCTAssertEqual(sampled.luma[39], 200)

        let mask = try XCTUnwrap(learn(same(disc(centreX: 20, centreY: 15, radius: 13))))
        let image = try XCTUnwrap(mask.tintImage())
        XCTAssertEqual(image.width, 40)
        XCTAssertEqual(image.height, 30)
    }
}
