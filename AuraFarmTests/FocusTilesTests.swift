import CoreVideo
import XCTest

@testable import AuraFarm

final class FocusTilesTests: XCTestCase {
    private let size = 640
    private var box: CGRect { CGRect(x: 0, y: 0, width: size, height: size) }

    /// A frame of mid grey with `texture` inside the listed tiles (row * 8 + column).
    private func frame(
        textured tiles: Set<Int> = [], frequency: Double = 0.9, amplitude: Double = 60,
        base: Double = 128, scale: Double = 1, dark: Set<Int> = [], saturated: Set<Int> = []
    ) -> CVPixelBuffer {
        let tile = size / 8
        return SyntheticFrame.make(width: size, height: size) { x, y in
            let index = (y / tile) * 8 + (x / tile)
            if dark.contains(index) { return 5 }
            if saturated.contains(index), (x + y) % 10 == 0 { return 255 }
            var value = base
            if tiles.contains(index) {
                value += amplitude * sin(Double(x) * frequency) * sin(Double(y) * frequency)
            }
            return UInt8(max(0, min(254, value * scale)))
        }
    }

    func testAFlatImageHasNoActiveTiles() throws {
        let reading = try XCTUnwrap(FocusTiles.measure(of: frame(), in: box))
        XCTAssertEqual(reading.active, 0)
        XCTAssertEqual(reading.used, 64)
        XCTAssertEqual(reading.top, 0, accuracy: 1e-9)
    }

    func testOneSharpTileOnABlankViewIsFoundAndRaisesTop() throws {
        let flat = try XCTUnwrap(FocusTiles.measure(of: frame(), in: box))
        let reading = try XCTUnwrap(FocusTiles.measure(of: frame(textured: [19]), in: box))
        XCTAssertTrue(reading.topTiles.contains(19))
        XCTAssertEqual(reading.topTiles, reading.topTiles.sorted())
        XCTAssertGreaterThan(reading.top, flat.top)
        XCTAssertEqual(reading.active, 1)
    }

    func testTheSameTextureBlurredReadsLower() throws {
        let sharp = try XCTUnwrap(FocusTiles.measure(of: frame(textured: [19, 20]), in: box))
        let blurred = try XCTUnwrap(
            FocusTiles.measure(of: frame(textured: [19, 20], frequency: 0.12), in: box))
        XCTAssertLessThan(blurred.top, sharp.top)
    }

    func testScalingTheLumaByEightTenthsChangesTopByUnderFivePercent() throws {
        let tiles: Set<Int> = [18, 19, 26, 27]
        let normal = try XCTUnwrap(FocusTiles.measure(of: frame(textured: tiles), in: box))
        let dimmer = try XCTUnwrap(
            FocusTiles.measure(of: frame(textured: tiles, scale: 0.8), in: box))
        XCTAssertEqual(dimmer.top, normal.top, accuracy: 0.05 * normal.top)
    }

    func testASaturatedTileIsLeftOut() throws {
        let reading = try XCTUnwrap(FocusTiles.measure(of: frame(saturated: [10]), in: box))
        XCTAssertEqual(reading.used, 63)
        XCTAssertNil(reading.tileFine[10])
    }

    func testADarkTileIsLeftOut() throws {
        let reading = try XCTUnwrap(FocusTiles.measure(of: frame(dark: [0, 7]), in: box))
        XCTAssertEqual(reading.used, 62)
        XCTAssertNil(reading.tileFine[0])
        XCTAssertNil(reading.tileFine[7])
    }

    func testTooFewTilesGiveNoReading() {
        XCTAssertNil(FocusTiles.measure(of: frame(dark: Set(0..<50)), in: box))
    }

    func testMoreSampleAtTheSameSharpnessChangesTopFarLessThanTheWholeBox() throws {
        let few = frame(textured: [9, 10, 17, 18])
        let many = frame(textured: Set([9, 10, 11, 12, 17, 18, 19, 20, 25, 26, 27, 28, 33, 34, 35, 36]))
        let topFew = try XCTUnwrap(FocusTiles.measure(of: few, in: box)).top
        let topMany = try XCTUnwrap(FocusTiles.measure(of: many, in: box)).top
        let wholeFew = try XCTUnwrap(FrameAnalyzer.stats(of: few, in: box, step: 2)).sharpness
        let wholeMany = try XCTUnwrap(FrameAnalyzer.stats(of: many, in: box, step: 2)).sharpness
        let topChange = abs(topMany - topFew) / topFew
        let boxChange = abs(wholeMany - wholeFew) / wholeFew
        XCTAssertLessThan(topChange, 0.1)
        XCTAssertGreaterThan(boxChange, 1)
        XCTAssertLessThan(topChange, boxChange / 5)
    }
}
