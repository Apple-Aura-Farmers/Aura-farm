import SwiftUI
import XCTest

@testable import AuraFarm

/// Phase 2h part A3 and B: the display transform with the stage's straightening, and the sizes
/// the guide measures through it.
final class StraightPictureTests: XCTestCase {
    /// Frame pixels to the preview through a plain transform, standing in for the camera layer.
    private struct AffineMapper: FrameToView {
        var transform: CGAffineTransform
        func viewPoint(of point: CGPoint) -> CGPoint { point.applying(transform) }
        func viewRect(of rect: CGRect) -> CGRect { rect.applying(transform) }
    }

    /// The picture shown at half size and turned 10 degrees, as the preview shows a tilted stage.
    private var turned: AffineMapper {
        AffineMapper(
            transform: CGAffineTransform(scaleX: 0.5, y: 0.5).rotated(by: 10 * .pi / 180)
                .translatedBy(x: 30, y: 20))
    }

    private let circle = FieldCircle(centre: CGPoint(x: 640, y: 360), radius: 250)

    func testTheScaleAndTheRadiusFollowTheProbesNotTheBoundingBox() {
        let mapper = turned
        XCTAssertEqual(mapper.scale(at: circle.centre), 0.5, accuracy: 1e-9)
        XCTAssertEqual(mapper.viewRadius(of: circle), 125, accuracy: 1e-6)
        // The old measure, half the smaller side of the bounding box of the circle's square,
        // grows under the rotation: cos 10 + sin 10 = 1.158.
        let box = mapper.viewRect(
            of: CGRect(x: 390, y: 110, width: 500, height: 500))
        let oldRadius = Double(min(box.width, box.height)) / 2
        XCTAssertGreaterThan(oldRadius, 125 * 1.15)
    }

    func testTheGuideGeometryUsesTheProbeLengths() throws {
        let box = CGRect(x: 500, y: 220, width: 280, height: 280)
        let geometry = try XCTUnwrap(
            GuideGeometryHost.geometry(using: turned, box: box, circle: circle))
        XCTAssertEqual(geometry.pointsPerField, 140, accuracy: 1e-6, "280 px at 0.5 per px")
        XCTAssertEqual(geometry.fieldRadius, 125, accuracy: 1e-6)
        // Without a circle the radius is half a field.
        let plain = try XCTUnwrap(GuideGeometryHost.geometry(using: turned, box: box, circle: nil))
        XCTAssertEqual(plain.fieldRadius, 70, accuracy: 1e-6)
        // The axes are the turned ones: x goes 10 degrees below screen +x.
        XCTAssertEqual(atan2(geometry.axes.c, geometry.axes.a) * 180 / .pi, 10, accuracy: 1e-6)
    }

    func testStraighteningIsComposedWithTheFitAboutTheFieldCentre() throws {
        let axes = CentredFieldDemo.axes(tiltDegrees: 10)
        let crop = CGRect(x: 50, y: 50, width: 200, height: 200)
        let centre = CGPoint(x: crop.midX, y: crop.midY)
        let display = FramePreviewConverter.displayTransform(
            crop: crop, centre: centre, straightening: axes.straightening,
            viewSize: CGSize(width: 300, height: 300))
        // The field centre ends at the middle of the view.
        let middle = centre.applying(display)
        XCTAssertEqual(middle.x, 150, accuracy: 1e-9)
        XCTAssertEqual(middle.y, 150, accuracy: 1e-9)
        // A vector 10 degrees off horizontal (the X knob's direction) comes out horizontal, and
        // the Y knob's comes out vertical, at the fit's scale of 1.5.
        func linear(_ vector: CGPoint) -> CGPoint {
            CGPoint(
                x: display.a * vector.x + display.c * vector.y,
                y: display.b * vector.x + display.d * vector.y)
        }
        let x = linear(axes.xDirection)
        let y = linear(axes.yDirection)
        XCTAssertEqual(Double(x.y), 0, accuracy: 1e-9)
        XCTAssertEqual(Double(x.x), 1.5, accuracy: 0.03)
        XCTAssertEqual(Double(y.x), 0, accuracy: 1e-9)
        XCTAssertEqual(Double(y.y), 1.5, accuracy: 0.03)
        // The identity straightening is the plain fit.
        XCTAssertEqual(
            FramePreviewConverter.displayTransform(
                crop: crop, centre: centre, straightening: .identity,
                viewSize: CGSize(width: 300, height: 300)),
            FramePreviewConverter.fitTransform(of: crop, in: CGSize(width: 300, height: 300)))
    }

    func testTheOutlineOfTheBoxTurnsWithThePicture() {
        let corners = turned.viewPolygon(of: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(corners.count, 4)
        // A turned square has no horizontal edge.
        XCTAssertNotEqual(corners[0].y, corners[1].y, accuracy: 1)
        XCTAssertEqual(
            hypot(Double(corners[1].x - corners[0].x), Double(corners[1].y - corners[0].y)), 50,
            accuracy: 1e-6)
    }

    @MainActor
    func testTheSquareFullWidthPicturesRender() throws {
        let renderer = ImageRenderer(content: CentredFieldDemo())
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        let data = try XCTUnwrap(image.pngData())
        let url = FileManager.default.temporaryDirectory.appending(path: "square-pictures.png")
        try data.write(to: url)
        print("PREVIEW \(url.path) \(Int(image.size.width))x\(Int(image.size.height))")
        XCTAssertGreaterThan(data.count, 10_000)
    }
}
