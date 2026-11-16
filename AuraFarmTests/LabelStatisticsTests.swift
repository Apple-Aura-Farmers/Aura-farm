import XCTest

@testable import AuraFarm

final class LabelStatisticsTests: XCTestCase {
    private func row(_ label: String, contrast: Double, sharpness: Double = 0) -> MovementLogRow {
        MovementLogRow(
            seconds: 0, brightness: 100, sharpness: 999, contrast: 999,
            positionX: 0, positionY: 0, positionXFrames: 0, positionYFrames: 0, hops: 0, gaps: 0,
            isLost: false, event: "", label: label, mark: "", frameWidth: 1280, frameHeight: 720,
            boxSharpness: sharpness, boxContrast: contrast)
    }

    /// The whole-frame numbers (999 here) are dominated by the ring, so the table ignores them.
    func testNearestRankPercentiles() throws {
        let rows = (1...10).map { row("sample", contrast: Double($0), sharpness: Double($0 * 10)) }
        let summary = try XCTUnwrap(LabelStatistics.summaries(of: rows.shuffled()).first)
        XCTAssertEqual(summary.count, 10)
        XCTAssertEqual(summary.contrast, .init(p10: 1, median: 5, p90: 9))
        XCTAssertEqual(summary.sharpness, .init(p10: 10, median: 50, p90: 90))
    }

    func testOrderAndEmptyLabels() {
        let rows = [
            row("blurry", contrast: 1), row("sample", contrast: 2), row("", contrast: 3),
            row("other", contrast: 4),
        ]
        XCTAssertEqual(LabelStatistics.summaries(of: rows).map(\.label), ["sample", "blurry"])
        XCTAssertEqual(LabelStatistics.summaries(of: []), [])
    }

    func testASingleRow() throws {
        let summary = try XCTUnwrap(
            LabelStatistics.summaries(of: [row("blank", contrast: 7, sharpness: 0.5)]).first)
        XCTAssertEqual(summary.contrast, .init(p10: 7, median: 7, p90: 7))
        XCTAssertEqual(summary.sharpness, .init(p10: 0.5, median: 0.5, p90: 0.5))
    }
}
