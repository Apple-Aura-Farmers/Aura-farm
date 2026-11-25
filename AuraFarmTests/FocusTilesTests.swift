import CoreVideo
import XCTest

@testable import AuraFarm

final class FocusTilesTests: XCTestCase {
    private let size = 640
    private var box: CGRect { CGRect(x: 0, y: 0, width: size, height: size) }
    /// The round view the box is the focus square of (0.7 of its diameter, as in setup): the four
    /// outermost tiles reach to 0.99 of its radius, so they are left out.
    private var circle: FieldCircle {
        FieldCircle(centre: CGPoint(x: size / 2, y: size / 2), radius: Double(size) / 2 / 0.7)
    }

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
        let reading = try XCTUnwrap(FocusTiles.measure(of: frame(), in: box, circle: circle))
        XCTAssertEqual(reading.active, 0)
        XCTAssertEqual(reading.used, 60, "the four corner tiles reach past 0.95 of the radius")
        XCTAssertEqual(reading.top, 0, accuracy: 1e-9)
    }

    func testOneSharpTileOnABlankViewIsFoundAndRaisesTop() throws {
        let flat = try XCTUnwrap(FocusTiles.measure(of: frame(), in: box, circle: circle))
        let reading = try XCTUnwrap(FocusTiles.measure(of: frame(textured: [19]), in: box, circle: circle))
        XCTAssertTrue(reading.topTiles.contains(19))
        XCTAssertEqual(reading.topTiles, reading.topTiles.sorted())
        XCTAssertGreaterThan(reading.top, flat.top)
        XCTAssertEqual(reading.active, 1)
    }

    func testTheSameTextureBlurredReadsLower() throws {
        let sharp = try XCTUnwrap(FocusTiles.measure(of: frame(textured: [19, 20]), in: box, circle: circle))
        let blurred = try XCTUnwrap(
            FocusTiles.measure(of: frame(textured: [19, 20], frequency: 0.12), in: box, circle: circle))
        XCTAssertLessThan(blurred.top, sharp.top)
    }

    func testScalingTheLumaByEightTenthsChangesTopByUnderFivePercent() throws {
        let tiles: Set<Int> = [18, 19, 26, 27]
        let normal = try XCTUnwrap(FocusTiles.measure(of: frame(textured: tiles), in: box, circle: circle))
        let dimmer = try XCTUnwrap(
            FocusTiles.measure(of: frame(textured: tiles, scale: 0.8), in: box, circle: circle))
        XCTAssertEqual(dimmer.top, normal.top, accuracy: 0.05 * normal.top)
    }

    func testASaturatedTileIsLeftOut() throws {
        let reading = try XCTUnwrap(FocusTiles.measure(of: frame(saturated: [10]), in: box, circle: circle))
        XCTAssertEqual(reading.used, 59)
        XCTAssertNil(reading.tileFine[10])
    }

    func testADarkTileIsLeftOut() throws {
        let reading = try XCTUnwrap(FocusTiles.measure(of: frame(dark: [8, 15]), in: box, circle: circle))
        XCTAssertEqual(reading.used, 58)
        XCTAssertNil(reading.tileFine[8])
        XCTAssertNil(reading.tileFine[15])
    }

    func testTooFewTilesGiveNoReading() {
        XCTAssertNil(FocusTiles.measure(of: frame(dark: Set(0..<50)), in: box, circle: circle))
    }

    func testMoreSampleAtTheSameSharpnessChangesTopFarLessThanTheWholeBox() throws {
        let few = frame(textured: [9, 10, 17, 18])
        let many = frame(textured: Set([9, 10, 11, 12, 17, 18, 19, 20, 25, 26, 27, 28, 33, 34, 35, 36]))
        let topFew = try XCTUnwrap(FocusTiles.measure(of: few, in: box, circle: circle)).top
        let topMany = try XCTUnwrap(FocusTiles.measure(of: many, in: box, circle: circle)).top
        let wholeFew = try XCTUnwrap(FrameAnalyzer.stats(of: few, in: box, step: 2)).sharpness
        let wholeMany = try XCTUnwrap(FrameAnalyzer.stats(of: many, in: box, step: 2)).sharpness
        let topChange = abs(topMany - topFew) / topFew
        let boxChange = abs(wholeMany - wholeFew) / wholeFew
        XCTAssertLessThan(topChange, 0.1)
        XCTAssertGreaterThan(boxChange, 1)
        XCTAssertLessThan(topChange, boxChange / 5)
    }

    func testTilesAtTheRimAreLeftOut() throws {
        let reading = try XCTUnwrap(FocusTiles.measure(of: frame(), in: box, circle: circle))
        for corner in [0, 7, 56, 63] { XCTAssertNil(reading.tileFine[corner], "tile \(corner)") }
        XCTAssertNotNil(reading.tileFine[1])
        XCTAssertEqual(reading.tileCoarse.count, 64)
        XCTAssertNil(reading.tileCoarse[0])
        // A tighter circle leaves out more: tile 1's far corner is 400 px out, tile 27's 113.
        let tight = FieldCircle(centre: circle.centre, radius: Double(size) / 2)
        let smaller = try XCTUnwrap(FocusTiles.measure(of: frame(), in: box, circle: tight))
        XCTAssertNil(smaller.tileFine[1])
        XCTAssertNotNil(smaller.tileFine[27])
        XCTAssertLessThan(smaller.used, reading.used)
    }

    func testNoiseOnlyTilesGiveNoDetail() throws {
        let flat = try XCTUnwrap(FocusTiles.measure(of: frame(), in: box, circle: circle))
        XCTAssertNil(flat.detail)
        let one = try XCTUnwrap(
            FocusTiles.measure(of: frame(textured: [19]), in: box, circle: circle))
        XCTAssertEqual(one.active, 1)
        XCTAssertNil(one.detail, "fewer than two active tiles")
    }

    func testFineStructureScoresAboveABlurredCopyOfItself() throws {
        let tiles: Set<Int> = [18, 19, 26, 27]
        let sharp = try XCTUnwrap(
            FocusTiles.measure(of: frame(textured: tiles), in: box, circle: circle))
        let blurred = try XCTUnwrap(
            FocusTiles.measure(of: frame(textured: tiles, frequency: 0.12), in: box, circle: circle))
        XCTAssertGreaterThan(try XCTUnwrap(sharp.detail), try XCTUnwrap(blurred.detail))
    }
}
