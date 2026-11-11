import XCTest

@testable import AuraFarm

/// `offset(to:)` is Vision's alignment translation with the vertical flipped to top-down.
/// On these synthetic frames it comes out pointing the SAME way as the content's move: a
/// frame whose content moved right and down by 40 px reads (+40, +40). Real footage may
/// differ from this (see `CaptureViewModel.pictureMoved`, measured on a microscope), which
/// is why the lab has a screen-mapping picker; these tests only pin the convention down.
final class TravelOffsetTests: XCTestCase {
    private let size = 256

    /// Seeded noise, blurred a little so registration has structure to lock onto.
    private func texture() -> [Double] {
        let raw = SyntheticFrame.noise(width: size, height: size).map(Double.init)
        var out = raw
        for y in 1..<(size - 1) {
            for x in 1..<(size - 1) {
                var total = 0.0
                for dy in -1...1 { for dx in -1...1 { total += raw[(y + dy) * size + x + dx] } }
                out[y * size + x] = total / 9
            }
        }
        return out
    }

    private func frame(_ texture: [Double], shiftedBy shift: (x: Int, y: Int)) -> CVPixelBuffer {
        SyntheticFrame.make(width: size, height: size) { x, y in
            let sx = min(max(x - shift.x, 0), size - 1)
            let sy = min(max(y - shift.y, 0), size - 1)
            return UInt8(texture[sy * size + sx])
        }
    }

    func testOffsetMatchesAContentShiftInX() throws {
        let texture = texture()
        let travel = TravelSinceLastFrame()
        travel.hold(frame(texture, shiftedBy: (0, 0)))
        let offset = try XCTUnwrap(travel.offset(to: frame(texture, shiftedBy: (40, 0))))
        XCTAssertEqual(offset.x, 40, accuracy: 3)
        XCTAssertEqual(offset.y, 0, accuracy: 3)
    }

    func testOffsetMatchesAContentShiftInY() throws {
        let texture = texture()
        let travel = TravelSinceLastFrame()
        travel.hold(frame(texture, shiftedBy: (0, 0)))
        let offset = try XCTUnwrap(travel.offset(to: frame(texture, shiftedBy: (0, 40))))
        XCTAssertEqual(offset.x, 0, accuracy: 3)
        // Top-down: content moved down the frame, and the flip makes that positive.
        XCTAssertEqual(offset.y, 40, accuracy: 3)
    }

    func testDistanceIsTheLengthOfTheOffset() throws {
        let texture = texture()
        let travel = TravelSinceLastFrame()
        let target = frame(texture, shiftedBy: (30, 20))
        travel.hold(frame(texture, shiftedBy: (0, 0)))
        let offset = try XCTUnwrap(travel.offset(to: target))
        let distance = try XCTUnwrap(travel.distance(to: target))
        XCTAssertEqual(distance, hypot(offset.x, offset.y), accuracy: 0.0001)
    }

    func testNoOffsetWithoutAHeldFrame() {
        let texture = texture()
        XCTAssertNil(TravelSinceLastFrame().offset(to: frame(texture, shiftedBy: (0, 0))))
    }

    /// An eyepiece: a static dark ring around a round field. The texture moves inside the
    /// field only.
    private func ringFrame(_ texture: [Double], shiftedBy dx: Int) -> CVPixelBuffer {
        let centre = Double(size) / 2
        return SyntheticFrame.make(width: size, height: size) { [size] x, y in
            guard hypot(Double(x) - centre, Double(y) - centre) <= Double(size) * 0.4 else {
                return 2
            }
            return UInt8(texture[y * size + min(max(x - dx, 0), size - 1)])
        }
    }

    func testAStaticRingHidesTheMovementUnlessRegistrationStaysInsideTheField() throws {
        let texture = texture()
        let held = ringFrame(texture, shiftedBy: 0)
        let moved = ringFrame(texture, shiftedBy: 40)

        let whole = TravelSinceLastFrame()
        whole.hold(held)
        let blind = try XCTUnwrap(whole.offset(to: moved))
        XCTAssertLessThan(hypot(blind.x, blind.y), 10, "the ring pins the answer near 0")

        // The region is learned the way the lab does: a field mask from sampled luma.
        var builder = FieldMaskBuilder(
            width: size, height: size, thresholds: .init(framesToLearn: 3))
        let sampled = try XCTUnwrap(LumaGrid.sample(of: held, step: 8))
        for _ in 0..<3 {
            builder.add(luma: sampled.luma, gridWidth: sampled.width, gridHeight: sampled.height)
        }
        let square = try XCTUnwrap(try XCTUnwrap(builder.result()).registrationRect)
        let frameSize = CGSize(width: size, height: size)

        let inside = TravelSinceLastFrame()
        inside.regionOfInterest = EyepieceField.visionRegion(of: square, frameSize: frameSize)
        inside.hold(held)
        let offset = try XCTUnwrap(inside.offset(to: moved))
        // The same convention as the tests above: content moved +40, the offset reads +40.
        XCTAssertEqual(offset.x, 40, accuracy: 3)
        XCTAssertEqual(offset.y, 0, accuracy: 3)
    }
}
