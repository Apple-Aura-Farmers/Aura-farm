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

    func testACentredFieldIsItsBoundingSquareWithTheMargin() {
        // Was the whole frame; now the square of 2 x 300 x 1.02 = 612 px.
        let rect = FieldCentring.cropRect(
            centre: CGPoint(x: 640, y: 360), radius: 300, frameSize: frame)
        XCTAssertEqual(rect, CGRect(x: 334, y: 54, width: 612, height: 612))
        assertInsideAndCentred(rect, on: CGPoint(x: 640, y: 360))
    }

    func testAFieldTowardTheBottomLeftIsASquareCentredOnIt() {
        // Was 800 x 340 (the largest rectangle). 190 x 1.02 = 193.8: room is 220 below, so the
        // square is 386 and nothing is shrunk.
        let centre = CGPoint(x: 420, y: 500)
        let rect = FieldCentring.cropRect(centre: centre, radius: 190, frameSize: frame)
        XCTAssertEqual(rect, CGRect(x: 227, y: 307, width: 386, height: 386))
        assertInsideAndCentred(rect, on: centre)
    }

    func testACircleNearAnEdgeShrinksTheSquareStillCentred() {
        // 20 px from the bottom edge: the square shrinks to 40.
        let centre = CGPoint(x: 400, y: 700)
        let rect = FieldCentring.cropRect(centre: centre, radius: 300, frameSize: frame)
        XCTAssertEqual(rect, CGRect(x: 380, y: 680, width: 40, height: 40))
        assertInsideAndCentred(rect, on: centre)
    }

    func testACropUnderTheMinimumSideIsTheWholeFrame() {
        let rect = FieldCentring.cropRect(
            centre: CGPoint(x: 6, y: 360), radius: 200, frameSize: frame)
        XCTAssertEqual(rect, CGRect(origin: .zero, size: frame))
    }

    func testAFractionalCentreStaysInsideAndWithinAPixelOfCentred() {
        for centre in [
            CGPoint(x: 400.4, y: 550.6), CGPoint(x: 639.5, y: 360.5), CGPoint(x: 1000.9, y: 100.2),
            CGPoint(x: 117.3, y: 619.9),
        ] {
            let rect = FieldCentring.cropRect(centre: centre, radius: 150, frameSize: frame)
            if rect.size == frame { continue }
            assertInsideAndCentred(rect, on: centre)
            XCTAssertEqual(rect.width, rect.height, "a square")
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
}
