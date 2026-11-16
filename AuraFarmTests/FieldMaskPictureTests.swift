import XCTest

@testable import AuraFarm

final class FieldMaskPictureTests: XCTestCase {
    private let width = 20
    private let height = 10

    private func pixel(_ rgba: [UInt8], _ x: Int, _ y: Int) -> [UInt8] {
        let index = (y * width + x) * 4
        return Array(rgba[index..<index + 4])
    }

    private func maskWith(eyepiece: (Int, Int) -> Bool) -> FieldMask {
        FieldMask(
            gridWidth: width, gridHeight: height, gridStep: 8,
            eyepiece: (0..<(width * height)).map { eyepiece($0 % width, $0 / width) },
            openShare: 0.5, registrationRect: nil)
    }

    func testTheSizeIsTheGridsAndEveryPixelIsOpaque() {
        let rgba = FieldMaskPicture.rgba(
            luma: [UInt8](repeating: 100, count: width * height), gridWidth: width,
            gridHeight: height, mask: nil, registrationRect: nil, gridStep: 8)
        XCTAssertEqual(rgba.count, width * height * 4)
        XCTAssertTrue(stride(from: 3, to: rgba.count, by: 4).allSatisfy { rgba[$0] == 255 })
    }

    func testLumaPassesThroughAsGreyWhereThereIsNoMaskOrBox() {
        let luma = (0..<(width * height)).map { UInt8($0 % 200) }
        let rgba = FieldMaskPicture.rgba(
            luma: luma, gridWidth: width, gridHeight: height, mask: nil, registrationRect: nil,
            gridStep: 8)
        XCTAssertEqual(pixel(rgba, 3, 2), [43, 43, 43, 255])
    }

    func testAMaskedCellIsTintedRedAndAnOpenCellIsLeftGrey() {
        let mask = maskWith { x, _ in x < 5 }
        let rgba = FieldMaskPicture.rgba(
            luma: [UInt8](repeating: 100, count: width * height), gridWidth: width,
            gridHeight: height, mask: mask, registrationRect: nil, gridStep: 8)
        let masked = pixel(rgba, 2, 5)
        XCTAssertGreaterThan(masked[0], masked[1])
        XCTAssertEqual(masked[1], masked[2])
        XCTAssertEqual(pixel(rgba, 10, 5), [100, 100, 100, 255])
    }

    func testTheBoxBorderIsYellowOneCellWideAndTheInsideKeepsItsLuma() {
        // A box from pixel (40, 16) to (120, 64): cells 5...14 across, 2...7 down.
        let rgba = FieldMaskPicture.rgba(
            luma: [UInt8](repeating: 100, count: width * height), gridWidth: width,
            gridHeight: height, mask: nil, registrationRect: CGRect(x: 40, y: 16, width: 80, height: 48),
            gridStep: 8)
        XCTAssertEqual(pixel(rgba, 5, 2), [255, 220, 0, 255], "corner")
        XCTAssertEqual(pixel(rgba, 10, 2), [255, 220, 0, 255], "top edge")
        XCTAssertEqual(pixel(rgba, 14, 5), [255, 220, 0, 255], "right edge")
        XCTAssertEqual(pixel(rgba, 10, 7), [255, 220, 0, 255], "bottom edge")
        XCTAssertEqual(pixel(rgba, 10, 4), [100, 100, 100, 255], "inside")
        XCTAssertEqual(pixel(rgba, 3, 4), [100, 100, 100, 255], "outside")
    }

    func testAMaskOfAnotherSizeAndATooSmallLumaAreHandled() throws {
        let other = FieldMask(
            gridWidth: 3, gridHeight: 3, gridStep: 8, eyepiece: [Bool](repeating: true, count: 9),
            openShare: 0, registrationRect: nil)
        let rgba = FieldMaskPicture.rgba(
            luma: [UInt8](repeating: 100, count: width * height), gridWidth: width,
            gridHeight: height, mask: other, registrationRect: nil, gridStep: 8)
        XCTAssertEqual(pixel(rgba, 0, 0), [100, 100, 100, 255], "the odd mask is ignored")
        XCTAssertTrue(
            FieldMaskPicture.rgba(
                luma: [1, 2, 3], gridWidth: width, gridHeight: height, mask: nil,
                registrationRect: nil, gridStep: 8
            ).isEmpty)
        let image = try XCTUnwrap(
            FieldMaskPicture.image(
                luma: [UInt8](repeating: 100, count: width * height), gridWidth: width,
                gridHeight: height, mask: nil, registrationRect: nil, gridStep: 8))
        XCTAssertEqual(image.width, width)
        XCTAssertEqual(image.height, height)
    }
}
