import XCTest

@testable import AuraFarm

final class AdviceBasisTests: XCTestCase {
    private func context(
        _ counts: [String: Int], frames: Int = 12, moisture: SampleDetails.Moisture = .flooded,
        stage: SampleDetails.CropStage? = nil, plot: String? = nil, history: Int = 0
    ) -> AdviceContext {
        let result = SoilResult(
            sampleID: "A12", recordedAt: .now, framesKept: frames, moisture: moisture, countsByClass: counts,
            sweep: nil, plotName: plot, cropStage: stage)
        let past = PastResult(
            recordedAt: .distantPast, moisture: .flooded, cropStage: nil, organismsPerFrame: 1,
            interpretedKinds: 2, level: .fair)
        return AdviceContextBuilder().context(
            for: result, estimate: PlaceholderSoilHealthEstimator().estimate(result),
            history: Array(repeating: past, count: history))
    }

    func testTheFullLine() {
        let context = context(
            ["euglena": 30, "phacus": 8, "paramecium": 3, "stentor": 6, "volvox": 4], stage: .tillering,
            plot: "North 2", history: 2)

        XCTAssertEqual(
            AdviceBasis.line(for: context),
            "Based on 41 organisms (3 kinds) in 12 frames, flooded, tillering, and 2 earlier samples of "
                + "North 2. 10 others weren't used.")
    }

    func testPlainCaseHasOnlyTheCountsAndMoisture() {
        XCTAssertEqual(
            AdviceBasis.line(for: context(["paramecium": 9, "amoeba": 3], moisture: .drained)),
            "Based on 12 organisms (2 kinds) in 12 frames, drained.")
    }

    func testSingularForms() {
        XCTAssertEqual(
            AdviceBasis.line(for: context(["paramecium": 1], frames: 1, plot: "A", history: 1)),
            "Based on 1 organism (1 kind) in 1 frame, flooded, and 1 earlier sample of A.")
        XCTAssertEqual(
            AdviceBasis.line(for: context(["paramecium": 5, "stentor": 1])),
            "Based on 5 organisms (1 kind) in 12 frames, flooded. 1 other wasn't used.")
    }

    func testHistoryNeedsAPlotName() {
        XCTAssertEqual(
            AdviceBasis.line(for: context(["paramecium": 5], plot: nil, history: 2)),
            "Based on 5 organisms (1 kind) in 12 frames, flooded.")
    }

    func testNothingReadableSaysSo() {
        XCTAssertEqual(
            AdviceBasis.line(for: context(["stentor": 6, "volvox": 5])),
            "Nothing in this sample could be read yet. 11 organisms weren't used.")
        XCTAssertEqual(
            AdviceBasis.line(for: context(["stentor": 1])),
            "Nothing in this sample could be read yet. 1 organism wasn't used.")
    }

    func testZeroOrganismsIsNeverWritten() {
        for counts in [["stentor": 6], ["stentor": 1, "volvox": 1], [:], ["paramecium": 4]] as [[String: Int]]
        {
            let line = AdviceBasis.line(for: context(counts)) ?? ""
            XCTAssertFalse(line.contains("0 organisms"), line)
            XCTAssertFalse(line.contains("0 kinds"), line)
        }
    }

    func testNothingCountedHasNoLine() {
        XCTAssertNil(AdviceBasis.line(for: context([:])))
    }
}
