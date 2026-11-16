import XCTest

@testable import AuraFarm

final class FrameStatsTests: XCTestCase {
    func testUniformGreyHasNoContrastAndNoSharpness() throws {
        let buffer = SyntheticFrame.make(width: 64, height: 64) { _, _ in 128 }
        let stats = try XCTUnwrap(FrameAnalyzer.stats(of: buffer))
        XCTAssertEqual(stats.brightness, 128, accuracy: 0.001)
        XCTAssertEqual(stats.contrast, 0, accuracy: 0.001)
        XCTAssertEqual(stats.sharpness, 0, accuracy: 0.001)
    }

    func testCheckerboardIsHighContrastAndSharp() throws {
        let buffer = SyntheticFrame.make(width: 64, height: 64) { x, y in
            ((x / 2 + y / 2) % 2 == 0) ? 0 : 255
        }
        let stats = try XCTUnwrap(FrameAnalyzer.stats(of: buffer))
        XCTAssertGreaterThan(stats.contrast, 100)
        XCTAssertGreaterThan(stats.sharpness, 1000)
    }

    func testGradientHasContrastButLittleSharpness() throws {
        let buffer = SyntheticFrame.make(width: 64, height: 64) { x, _ in UInt8(x * 4) }
        let stats = try XCTUnwrap(FrameAnalyzer.stats(of: buffer))
        XCTAssertGreaterThan(stats.contrast, 30)
        XCTAssertLessThan(stats.sharpness, 1)
    }

    func testBrightnessAndSharpnessAgreeWithStats() throws {
        let noise = SyntheticFrame.noise(width: 64, height: 64)
        let buffer = SyntheticFrame.make(width: 64, height: 64) { x, y in noise[y * 64 + x] }
        let stats = try XCTUnwrap(FrameAnalyzer.stats(of: buffer))
        let pair = try XCTUnwrap(FrameAnalyzer.brightnessAndSharpness(of: buffer))
        XCTAssertEqual(pair.brightness, stats.brightness)
        XCTAssertEqual(pair.sharpness, stats.sharpness)
    }
}
