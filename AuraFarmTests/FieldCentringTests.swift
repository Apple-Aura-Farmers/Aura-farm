import SwiftUI
import XCTest

@testable import AuraFarm

final class FieldCentringTests: XCTestCase {
    private let frame = CGSize(width: 1280, height: 720)

    private func assertInsideAndCentred(
        _ rect: CGRect, on centre: CGPoint, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(rect.minX, 0, file: file, line: line)
        XCTAssertGreaterThanOrEqual(rect.minY, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(rect.maxX, frame.width, file: file, line: line)
        XCTAssertLessThanOrEqual(rect.maxY, frame.height, file: file, line: line)
        XCTAssertEqual(rect.midX, centre.x, accuracy: 1, file: file, line: line)
        XCTAssertEqual(rect.midY, centre.y, accuracy: 1, file: file, line: line)
        XCTAssertEqual(rect.minX, rect.minX.rounded(), file: file, line: line)
        XCTAssertEqual(rect.width, rect.width.rounded(), file: file, line: line)
    }

    func testACentredFieldGivesTheWholeFrame() {
        let rect = FieldCentring.cropRect(centre: CGPoint(x: 640, y: 360), frameSize: frame)
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 1280, height: 720))
    }

    func testAFieldTowardTheBottomLeftTrimsTheTopAndTheRight() {
        // 400 from the left, 550 down: the field is 400 from the left edge and 170 from the
        // bottom, so the crop is 800 wide and 340 tall.
        let centre = CGPoint(x: 400, y: 550)
        let rect = FieldCentring.cropRect(centre: centre, frameSize: frame)
        XCTAssertEqual(rect, CGRect(x: 0, y: 380, width: 800, height: 340))
        XCTAssertEqual(rect.minX, 0, "nothing trimmed on the left")
        XCTAssertEqual(rect.maxY, 720, "nothing trimmed at the bottom")
        XCTAssertEqual(rect.minY, 380, "the top is trimmed by 380")
        XCTAssertEqual(frame.width - rect.maxX, 480, "the right is trimmed by 480")
        assertInsideAndCentred(rect, on: centre)
    }

    func testAFieldNearACornerGivesASmallRect() {
        let centre = CGPoint(x: 60, y: 700)
        let rect = FieldCentring.cropRect(centre: centre, frameSize: frame)
        XCTAssertEqual(rect, CGRect(x: 0, y: 680, width: 120, height: 40))
        assertInsideAndCentred(rect, on: centre)
    }

    func testACropUnderTheMinimumSideIsTheWholeFrame() {
        let rect = FieldCentring.cropRect(centre: CGPoint(x: 6, y: 360), frameSize: frame)
        XCTAssertEqual(rect, CGRect(origin: .zero, size: frame))
    }

    func testAFractionalCentreStaysInsideAndWithinAPixelOfCentred() {
        for centre in [
            CGPoint(x: 400.4, y: 550.6), CGPoint(x: 639.5, y: 360.5), CGPoint(x: 1000.9, y: 100.2),
            CGPoint(x: 17.3, y: 719.9),
        ] {
            let rect = FieldCentring.cropRect(centre: centre, frameSize: frame)
            if rect.size == frame { continue }
            assertInsideAndCentred(rect, on: centre)
        }
    }

    func testTheMaskAndTheCircleGiveTheSameCrop() throws {
        let circle = FieldCircle(centre: CGPoint(x: 420, y: 500), radius: 190)
        let mask = circle.mask(frameSize: frame)
        let fromMask = try XCTUnwrap(FieldCentring.cropRect(for: mask, frameSize: frame))
        let fromCircle = FieldCentring.cropRect(for: circle, frameSize: frame)
        XCTAssertEqual(fromMask.midX, fromCircle.midX, accuracy: 6, "within a grid cell")
        XCTAssertEqual(fromMask.midY, fromCircle.midY, accuracy: 6)
        assertInsideAndCentred(fromMask, on: try XCTUnwrap(FieldCircle(fitting: mask)).centre)
    }

    func testAMaskWithNoOpenCellsGivesNoCrop() {
        let mask = FieldMask(
            gridWidth: 2, gridHeight: 2, gridStep: 8, eyepiece: [true, true, true, true],
            openShare: 0, registrationRect: nil)
        XCTAssertNil(FieldCentring.cropRect(for: mask, frameSize: CGSize(width: 16, height: 16)))
    }

    // MARK: Lab display (DEBUG)

    func testTheFitTransformPutsTheCropCentredAndAsLargeAsFits() {
        let view = CGSize(width: 400, height: 300)
        // A crop centred in the view, half its size: scaled up to fill.
        let crop = CGRect(x: 100, y: 75, width: 200, height: 150)
        let transform = FramePreviewConverter.fitTransform(of: crop, in: view)
        XCTAssertEqual(transform.a, 2, accuracy: 1e-9)
        XCTAssertEqual(CGPoint(x: crop.midX, y: crop.midY).applying(transform).x, 200, accuracy: 1e-9)
        XCTAssertEqual(CGPoint(x: crop.midX, y: crop.midY).applying(transform).y, 150, accuracy: 1e-9)

        // A crop off to the bottom left: its middle goes to the middle of the view.
        let low = CGRect(x: 0, y: 150, width: 200, height: 150)
        let moved = FramePreviewConverter.fitTransform(of: low, in: view)
        let middle = CGPoint(x: low.midX, y: low.midY).applying(moved)
        XCTAssertEqual(middle.x, 200, accuracy: 1e-9)
        XCTAssertEqual(middle.y, 150, accuracy: 1e-9)
        // And the part of the crop inside the view fills it exactly on its tighter side.
        XCTAssertEqual(moved.a, 2, accuracy: 1e-9)

        // A crop that runs past what the view shows is trimmed to it, still centred.
        let big = CGRect(x: -100, y: -100, width: 600, height: 500)
        XCTAssertEqual(FramePreviewConverter.fitTransform(of: big, in: view).a, 1, accuracy: 1e-9)
        XCTAssertEqual(FramePreviewConverter.fitTransform(of: .zero, in: view), .identity)
    }

    @MainActor
    func testTheCentredAndUncroppedPreviewsRender() throws {
        let renderer = ImageRenderer(content: CentredFieldDemo())
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        let data = try XCTUnwrap(image.pngData())
        let url = FileManager.default.temporaryDirectory.appending(path: "centred-field-preview.png")
        try data.write(to: url)
        print("PREVIEW \(url.path) \(Int(image.size.width))x\(Int(image.size.height))")
        XCTAssertGreaterThan(data.count, 10_000)
    }
}
