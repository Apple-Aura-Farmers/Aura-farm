import ImageIO
import XCTest

@testable import AuraFarm

/// Phase 2n part A: both box crops are high-passed before Vision sees them. The fixtures are 400 px
/// crops centred on (722, 415) of two snapshots of the same still view (16 Nov 2026 14:20, soil),
/// frame-000.10 and frame-003.47. Unfiltered, that pair read +-242 px in x although nothing moved.
final class RegistrationFilterTests: XCTestCase {
    private let box = CGRect(x: 39, y: 39, width: 322, height: 322)
    private let registration = BoxRegistration()

    private func fixture(_ name: String) throws -> (bytes: [UInt8], width: Int, height: Int) {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: name, withExtension: "png"), "missing \(name).png")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return try XCTUnwrap(RegistrationFilter.luma(of: image))
    }

    private func buffer(
        _ luma: (bytes: [UInt8], width: Int, height: Int), shiftedBy shift: CGPoint = .zero
    ) -> CVPixelBuffer {
        let dx = Int(shift.x)
        let dy = Int(shift.y)
        return SyntheticFrame.make(width: luma.width, height: luma.height) { x, y in
            let sx = min(max(x - dx, 0), luma.width - 1)
            let sy = min(max(y - dy, 0), luma.height - 1)
            return luma.bytes[sy * luma.width + sx]
        }
    }

    func testTheStillPairOfGhostFramesReadsZero() throws {
        let a = buffer(try fixture("ghost-a"))
        let b = buffer(try fixture("ghost-b"))
        let filtered = try XCTUnwrap(registration.offset(from: a, to: b, box: box))
        XCTAssertEqual(Double(filtered.x), 0, accuracy: 3)
        XCTAssertEqual(Double(filtered.y), 0, accuracy: 3)
        // What the same pair gives without the filter (recorded, not asserted).
        registration.filter = nil
        let raw = registration.offset(from: a, to: b, box: box)
        print("ghost pair unfiltered: \(String(describing: raw)), filtered: \(filtered)")
    }

    func testShiftsOfTheBoxOverGhostAAreRecoveredOnBothAxes() throws {
        let luma = try fixture("ghost-a")
        let held = buffer(luma)
        let shifts: [(Double, Double)] = [
            (10, 0), (30, 0), (60, 0), (-40, 0), (0, 10), (0, 30), (0, 60), (0, -40), (25, 25),
        ]
        for (dx, dy) in shifts {
            let moved = buffer(luma, shiftedBy: CGPoint(x: dx, y: dy))
            let read = try XCTUnwrap(registration.offset(from: held, to: moved, box: box))
            XCTAssertEqual(Double(read.x), dx, accuracy: 3, "shift (\(dx), \(dy)) read \(read)")
            XCTAssertEqual(Double(read.y), dy, accuracy: 3, "shift (\(dx), \(dy)) read \(read)")
        }
    }

    func testAStrongLinearGradientOnATextureStillRegisters() throws {
        let size = 256
        let texture = SyntheticFrame.smoothNoise(size: size)
        func frame(shiftX: Int, shiftY: Int) -> CVPixelBuffer {
            SyntheticFrame.make(width: size, height: size) { x, y in
                let sx = min(max(x - shiftX, 0), size - 1)
                let sy = min(max(y - shiftY, 0), size - 1)
                // The texture rides on a strong ramp that does not move with it.
                return UInt8(min(40 + texture[sy * size + sx] * 0.4 + Double(x) * 0.5, 255))
            }
        }
        let area = CGRect(x: 20, y: 20, width: 200, height: 200)
        let read = try XCTUnwrap(
            registration.offset(
                from: frame(shiftX: 0, shiftY: 0), to: frame(shiftX: 7, shiftY: 9), box: area))
        XCTAssertEqual(Double(read.x), 7, accuracy: 3)
        XCTAssertEqual(Double(read.y), 9, accuracy: 3)
    }

    func testTheStoredPictureGetsTheSameFilter() throws {
        // The stored copy is the raw crop; registering it against the live buffer must agree with
        // registering two live buffers.
        let luma = try fixture("ghost-a")
        let held = buffer(luma)
        let moved = buffer(luma, shiftedBy: CGPoint(x: 20, y: -15))
        let context = CIContext()
        let stored = try XCTUnwrap(registration.copy(of: held, box: box, context: context))
        let fromStored = try XCTUnwrap(registration.offset(fromStored: stored, to: moved, box: box))
        let live = try XCTUnwrap(registration.offset(from: held, to: moved, box: box))
        XCTAssertEqual(Double(fromStored.x), Double(live.x), accuracy: 2)
        XCTAssertEqual(Double(fromStored.y), Double(live.y), accuracy: 2)
        XCTAssertEqual(Double(fromStored.x), 20, accuracy: 3)
    }

    func testTimePerFrameWithAndWithoutTheFilter() throws {
        // Reported, not asserted tightly: a simulator debug build is far slower than a phone.
        // One tracked frame is two registrations (against the previous frame and against the
        // anchor), on a fresh buffer each time, as in a run.
        let luma = try fixture("ghost-a")
        let frames = (0..<21).map { buffer(luma, shiftedBy: CGPoint(x: Double($0), y: 0)) }
        func milliseconds(_ filter: RegistrationFilterThresholds?) -> Double {
            registration.filter = filter
            let started = ContinuousClock.now
            for index in 1..<frames.count {
                _ = registration.offset(from: frames[index - 1], to: frames[index], box: box)
                _ = registration.offset(from: frames[0], to: frames[index], box: box)
            }
            let taken = ContinuousClock.now - started
            let total =
                Double(taken.components.seconds) * 1000
                + Double(taken.components.attoseconds) / 1e15
            return total / 20
        }
        _ = milliseconds(nil)  // warm-up: Vision's first calls are slow
        let before = milliseconds(nil)
        let after = milliseconds(RegistrationFilterThresholds())
        print("registration ms per frame (322 px box, 2 registrations): before \(before), after \(after)")
        XCTAssertLessThan(after, 500)
    }
}
