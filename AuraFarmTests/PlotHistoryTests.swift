import XCTest

@testable import AuraFarm

final class PlotHistoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_000_000)
    private let day: TimeInterval = 86_400

    private func sweep(
        _ name: String, plot: String?, daysAgo: Double, counts: [String: Int]? = ["paramecium": 12],
        hasManifest: Bool = true
    ) -> SavedSweep {
        let recordedAt = now.addingTimeInterval(-daysAgo * day)
        let details = SampleDetails(
            sampleID: name, field: 1, moisture: .flooded, gramsOfSoil: 1, millilitresScanned: nil,
            recordedAt: recordedAt, plotName: plot, cropStage: .tillering)
        return SavedSweep(
            url: URL(filePath: "/tmp/\(name)", directoryHint: .isDirectory),
            manifest: hasManifest
                ? SweepManifest(
                    details: details, frameCount: 12, byteCount: 0, stoppedEarly: false,
                    organismCounts: counts)
                : nil,
            recordedAt: recordedAt, byteCount: 0, frameURLs: [], panoramaURL: nil)
    }

    private func result(plot: String?, sweep: SavedSweep? = nil) -> SoilResult {
        SoilResult(
            sampleID: "NOW", recordedAt: now, framesKept: 12, moisture: .flooded, countsByClass: [:],
            sweep: sweep, plotName: plot)
    }

    func testNoPlotNameMeansNoHistory() {
        let sweeps = [sweep("A", plot: "North 2", daysAgo: 5)]

        XCTAssertTrue(PlotHistory.earlierResults(for: result(plot: nil), among: sweeps).isEmpty)
        XCTAssertTrue(PlotHistory.earlierResults(for: result(plot: "  "), among: sweeps).isEmpty)
    }

    func testPlotNamesMatchTrimmedInAnyCase() {
        let sweeps = [sweep("A", plot: " north 2 ", daysAgo: 5), sweep("B", plot: "South", daysAgo: 6)]

        let history = PlotHistory.earlierResults(for: result(plot: "North 2"), among: sweeps)

        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.organismsPerFrame, 1)
        XCTAssertEqual(history.first?.interpretedKinds, 1)
        XCTAssertEqual(history.first?.cropStage, .tillering)
    }

    func testCurrentAndLaterSweepsAreLeftOut() {
        let current = sweep("NOW", plot: "North 2", daysAgo: 0)
        let sweeps = [
            current, sweep("LATER", plot: "North 2", daysAgo: -1), sweep("SAME", plot: "North 2", daysAgo: 0),
            sweep("EARLIER", plot: "North 2", daysAgo: 3),
        ]

        let history = PlotHistory.earlierResults(for: result(plot: "North 2", sweep: current), among: sweeps)

        XCTAssertEqual(history.map(\.recordedAt), [now.addingTimeInterval(-3 * day)])
    }

    func testUncountedSweepsAndSweepsWithoutManifestAreSkipped() {
        let sweeps = [
            sweep("UNCOUNTED", plot: "North 2", daysAgo: 1, counts: nil),
            sweep("NO-MANIFEST", plot: "North 2", daysAgo: 2, hasManifest: false),
            sweep("COUNTED", plot: "North 2", daysAgo: 3),
        ]

        let history = PlotHistory.earlierResults(for: result(plot: "North 2"), among: sweeps)

        XCTAssertEqual(history.map(\.recordedAt), [now.addingTimeInterval(-3 * day)])
    }

    func testNewestFirstWithTheLimit() {
        let sweeps = [1.0, 9, 4, 2, 7].map { sweep("S\($0)", plot: "North 2", daysAgo: $0) }

        let history = PlotHistory.earlierResults(for: result(plot: "North 2"), among: sweeps)

        XCTAssertEqual(history.map(\.recordedAt), [1.0, 2, 4].map { now.addingTimeInterval(-$0 * day) })
    }
}
