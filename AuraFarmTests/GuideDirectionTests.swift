import XCTest

@testable import AuraFarm

/// The guide's position must be where the VIEW is, and a target cross must stay glued to the
/// picture. Real registration, no reading override: content moving one way means the view
/// travelled the other.
final class GuideDirectionTests: XCTestCase {
    private let width = 640
    private let height = 480
    private let frames = 9
    private let step = 20
    private lazy var texture = SyntheticFrame.smoothNoise(size: 640)
    private let axes = GuideScreenAxes(a: 1, b: 0, c: 0, d: 1)

    private func frame(shiftedBy shift: (x: Int, y: Int)) -> CVPixelBuffer {
        SyntheticFrame.make(width: width, height: height) { [width, height, texture] x, y in
            let sx = min(max(x - shift.x, 0), width - 1)
            let sy = min(max(y - shift.y, 0), height - 1)
            _ = height
            return UInt8(texture[sy * 640 + sx])
        }
    }

    private struct Run {
        var positions: [CGPoint]
        var guide: [CGPoint]
        var hops: Int
        var boxSide: Double
        var crosses: [CGPoint]
    }

    private func run(contentMovesBy direction: (x: Int, y: Int)) -> Run {
        let size = CGSize(width: width, height: height)
        let box = EyepieceField.centreSquare(frameSize: size)
        let side = Double(box.width)
        let tracker = SlideTracker()
        var positions: [CGPoint] = []
        var guide: [CGPoint] = []
        var hops = 0
        for index in 0..<frames {
            let reading = tracker.track(
                frame(shiftedBy: (direction.x * step * index, direction.y * step * index)),
                box: box, frameSize: size, seconds: Double(index) * 0.1)
            positions.append(reading.position)
            guide.append(axes.guideFields(forTrackerPosition: reading.position, pointsPerField: side))
            hops = reading.hops
        }
        // A fixed spot half a field to the right of where the view started (and half a field
        // down), seen from each position.
        let target = CGPoint(x: Double(guide[0].x) + 0.5, y: Double(guide[0].y) + 0.5)
        let crosses = guide.map { position -> CGPoint in
            let model = GuideOverlayModel.make(
                step: GuideStep(
                    instruction: .move(toward: .zero), target: target, capture: nil, stateName: "",
                    column: 1, isFinished: false, finishReason: nil),
                position: position, tracking: .tracking, centre: .zero, pointsPerField: side,
                fieldRadius: 5000, alignToleranceFields: 0.15)
            guard case .cross(let at, _) = model.mark else { return .zero }
            return at
        }
        return Run(positions: positions, guide: guide, hops: hops, boxSide: side, crosses: crosses)
    }

    private func report(_ name: String, _ run: Run, moved: Double) {
        print(
            "DIRECTION \(name): hops \(run.hops) tracker last \(run.positions.last ?? .zero) "
                + "guide \(run.guide.first ?? .zero) -> \(run.guide.last ?? .zero) "
                + "cross \(run.crosses.first ?? .zero) -> \(run.crosses.last ?? .zero) content moved \(moved) px"
        )
    }

    func testContentMovingRightMeansTheViewTravelledLeftAndTheCrossFollowsThePicture() throws {
        let result = run(contentMovesBy: (1, 0))
        let moved = Double(step * (frames - 1))
        report("right", result, moved: moved)
        XCTAssertGreaterThanOrEqual(result.hops, 1)
        // A) the view went left.
        let dx = Double(result.guide[frames - 1].x - result.guide[0].x)
        XCTAssertEqual(
            dx, -moved / result.boxSide, accuracy: 0.25 * moved / result.boxSide + 3 / result.boxSide)
        // B) the cross moves the same way as the content, by about as much.
        let cross = Double(result.crosses[frames - 1].x - result.crosses[0].x)
        XCTAssertEqual(cross, moved, accuracy: 0.25 * moved + 3)
    }

    func testContentMovingDownMeansTheViewTravelledUpAndTheCrossFollowsThePicture() {
        let result = run(contentMovesBy: (0, 1))
        let moved = Double(step * (frames - 1))
        report("down", result, moved: moved)
        XCTAssertGreaterThanOrEqual(result.hops, 1)
        let dy = Double(result.guide[frames - 1].y - result.guide[0].y)
        XCTAssertEqual(
            dy, -moved / result.boxSide, accuracy: 0.25 * moved / result.boxSide + 3 / result.boxSide)
        let cross = Double(result.crosses[frames - 1].y - result.crosses[0].y)
        XCTAssertEqual(cross, moved, accuracy: 0.25 * moved + 3)
    }
}
