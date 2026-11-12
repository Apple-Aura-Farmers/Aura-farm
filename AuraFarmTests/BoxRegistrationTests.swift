import XCTest

@testable import AuraFarm

final class BoxRegistrationTests: XCTestCase {
    private let size = 256
    private lazy var texture = SyntheticFrame.smoothNoise(size: size)
    private let box = CGRect(x: 78, y: 78, width: 100, height: 100)

    private func textureValue(_ x: Int, _ y: Int, shiftedBy dx: Int, _ dy: Int = 0) -> UInt8 {
        let sx = min(max(x - dx, 0), size - 1)
        let sy = min(max(y - dy, 0), size - 1)
        return UInt8(70 + texture[sy * size + sx] * 0.5)
    }

    /// Texture moving by (dx, dy) inside a disc; a static dark ring outside it.
    private func ringFrame(dx: Int, dy: Int = 0) -> CVPixelBuffer {
        SyntheticFrame.make(width: size, height: size) { [self] x, y in
            guard hypot(Double(x) - 128, Double(y) - 128) <= 118 else { return 2 }
            return textureValue(x, y, shiftedBy: dx, dy)
        }
    }

    /// The same texture with no ring at all.
    private func plainFrame(dx: Int) -> CVPixelBuffer {
        SyntheticFrame.make(width: size, height: size) { [self] x, y in
            textureValue(x, y, shiftedBy: dx)
        }
    }

    func testSignAndSizeMatchTheWholeFramePathOnARingFreeFrame() throws {
        let travel = TravelSinceLastFrame()
        travel.hold(plainFrame(dx: 0))
        let reference = try XCTUnwrap(travel.offset(to: plainFrame(dx: 40)))

        let boxed = try XCTUnwrap(
            BoxRegistration().offset(from: ringFrame(dx: 0), to: ringFrame(dx: 40), box: box))
        XCTAssertEqual(boxed.x, reference.x, accuracy: 3)
        XCTAssertEqual(boxed.y, reference.y, accuracy: 3)
        XCTAssertEqual(abs(boxed.x), 40, accuracy: 3)
    }

    func testVerticalShiftKeepsTheSameSignConventionAsTheWholeFramePath() throws {
        let vertical = SyntheticFrame.make(width: size, height: size) { [self] x, y in
            textureValue(x, y, shiftedBy: 0, 30)
        }
        let base = SyntheticFrame.make(width: size, height: size) { [self] x, y in
            textureValue(x, y, shiftedBy: 0, 0)
        }
        let travel = TravelSinceLastFrame()
        travel.hold(base)
        let reference = try XCTUnwrap(travel.offset(to: vertical))
        let boxed = try XCTUnwrap(BoxRegistration().offset(from: base, to: vertical, box: box))
        XCTAssertEqual(boxed.y, reference.y, accuracy: 3)
        XCTAssertEqual(boxed.x, 0, accuracy: 3)
    }

    func testAStaticRingDoesNotPinTheAnswerAtZero() throws {
        let boxed = try XCTUnwrap(
            BoxRegistration().offset(from: ringFrame(dx: 0), to: ringFrame(dx: 25, dy: -10), box: box))
        XCTAssertEqual(boxed.x, 25, accuracy: 3)
        XCTAssertEqual(boxed.y, -10, accuracy: 3)
    }

    /// The held frame carries a decoy: a copy of what the box will see, away from the box.
    /// Only the held frame has it, so a match against the whole held frame has something to
    /// be tempted by; cropping both frames takes it out of reach.
    func testADecoyOutsideTheBoxCannotPullTheCroppedAnswer() throws {
        // Outside the box, paint what the box shows after a +12 shift.
        let heldWithDecoy = SyntheticFrame.make(width: size, height: size) { [self] x, y in
            if box.contains(CGPoint(x: x, y: y)) { return textureValue(x, y, shiftedBy: 0) }
            let source = CGPoint(x: x - 80, y: y + 0)
            if box.contains(source) {
                return textureValue(Int(source.x), Int(source.y), shiftedBy: 12)
            }
            return 20
        }
        let current = SyntheticFrame.make(width: size, height: size) { [self] x, y in
            box.contains(CGPoint(x: x, y: y)) ? textureValue(x, y, shiftedBy: 12) : 20
        }
        let boxed = try XCTUnwrap(
            BoxRegistration().offset(from: heldWithDecoy, to: current, box: box))
        XCTAssertEqual(boxed.x, 12, accuracy: 3, "the cropped answer is the real shift")

        // What the old path (region on the newer frame only) makes of the same pair. Recorded,
        // not asserted: whether Vision is tempted depends on the content.
        let travel = TravelSinceLastFrame()
        travel.hold(heldWithDecoy)
        travel.regionOfInterest = EyepieceField.visionRegion(
            of: box, frameSize: CGSize(width: size, height: size))
        let old = travel.offset(to: current)
        print("BoxRegistrationTests decoy: old path read \(String(describing: old)); new \(boxed)")
    }

    func testTooSmallABoxGivesNothing() {
        XCTAssertNil(
            BoxRegistration().offset(
                from: ringFrame(dx: 0), to: ringFrame(dx: 5), box: CGRect(x: 10, y: 10, width: 8, height: 8)))
    }

    func testBoxStatsSeeThroughTheRing() throws {
        // A bright blank field in a dark ring: the whole frame has plenty of contrast and edge,
        // the box holds none.
        let blank = SyntheticFrame.make(width: size, height: size) { x, y in
            hypot(Double(x) - 128, Double(y) - 128) <= 118 ? 100 : 2
        }
        let whole = try XCTUnwrap(FrameAnalyzer.stats(of: blank, step: 4))
        let inside = try XCTUnwrap(FrameAnalyzer.stats(of: blank, in: box, step: 4))
        print("box stats blank: whole \(whole) box \(inside)")
        XCTAssertLessThan(inside.contrast, 1)
        XCTAssertLessThan(inside.sharpness, 1)
        XCTAssertGreaterThan(whole.contrast, 20, "the ring dominates the whole-frame contrast")
        XCTAssertGreaterThan(whole.sharpness, inside.sharpness)

        let textured = try XCTUnwrap(FrameAnalyzer.stats(of: ringFrame(dx: 0), in: box, step: 4))
        print("box stats textured: \(textured)")
        XCTAssertGreaterThan(textured.sharpness, DetailThresholds().minBoxSharpness)
        XCTAssertGreaterThan(textured.contrast, inside.contrast)
    }

    func testBoxStatsOfAWholeFrameBoxMatchTheWholeFrameStats() throws {
        let frame = ringFrame(dx: 0)
        let whole = try XCTUnwrap(FrameAnalyzer.stats(of: frame, step: 4))
        let same = try XCTUnwrap(
            FrameAnalyzer.stats(
                of: frame, in: CGRect(x: 0, y: 0, width: size, height: size), step: 4))
        XCTAssertEqual(whole, same)
        XCTAssertNil(
            FrameAnalyzer.stats(of: frame, in: CGRect(x: 500, y: 500, width: 50, height: 50), step: 4))
    }
}
