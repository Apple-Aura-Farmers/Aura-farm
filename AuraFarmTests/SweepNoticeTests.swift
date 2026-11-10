import XCTest

@testable import AuraFarm

final class SweepNoticeTests: XCTestCase {
    func testASweepThatCameOutWholeSaysNothing() {
        XCTAssertTrue(SweepNotice.all(for: [sweep()]).isEmpty)
    }

    func testEachThingWrongWithASweepIsItsOwnNotice() {
        let awkward = sweep(
            panoramaProblem: "3 of 12 frames did not line up with the rest.",
            stoppedEarly: true,
            counts: nil
        )

        let kinds = SweepNotice.all(for: [awkward]).map(\.kind)

        XCTAssertEqual(kinds, [.framesDidNotJoin, .stoppedEarly, .notCounted])
    }

    func testASweepNothingCountedIsNotMistakenForOneThatFoundNothing() {
        XCTAssertEqual(SweepNotice.all(for: [sweep(counts: [:])]), [])
        XCTAssertEqual(SweepNotice.all(for: [sweep(counts: nil)]).map(\.kind), [.notCounted])
    }

    func testTheStoreIsMentionedOnceItIsFourFifthsFull() {
        let limit = Int64(50 * 1_000 * 1_000)
        let nearly = Int64(Double(limit) * SweepNotice.storeFullShare)

        XCTAssertEqual(SweepNotice.all(for: [sweep(bytes: nearly - 1)], limit: limit), [])
        XCTAssertEqual(
            SweepNotice.all(for: [sweep(bytes: nearly)], limit: limit).map(\.kind),
            [.storeNearlyFull]
        )
    }

    func testTheStoreComesBeforeTheSweepsAndIsAboutNoneOfThem() {
        let limit = Int64(1_000)
        let notices = SweepNotice.all(for: [sweep(bytes: limit, counts: nil)], limit: limit)

        XCTAssertEqual(notices.map(\.kind), [.storeNearlyFull, .notCounted])
        XCTAssertNil(notices.first?.sweep)
        XCTAssertNotNil(notices.last?.sweep)
    }

    func testANoticeIsNamedAfterTheFieldRatherThanTheFolder() {
        let named = SweepNotice.all(for: [sweep(sampleID: "Pak Wayan", counts: nil)])
        XCTAssertTrue(named.first?.title.hasPrefix("Pak Wayan") == true)

        // A sweep saved before the form asked for a name falls back to its folder.
        let unnamed = SweepNotice.all(for: [sweep(sampleID: "  ", counts: nil)])
        XCTAssertTrue(unnamed.first?.title.hasPrefix("sweep-1") == true)
    }

    func testASweepWithNoManifestRaisesNothingToActOn() {
        // The folder is listed either way, but there is nothing to say about it.
        let unreadable = SavedSweep(
            url: URL(filePath: "/tmp/sweep-1"),
            manifest: nil,
            recordedAt: .now,
            byteCount: 0,
            frameURLs: [],
            panoramaURL: nil
        )
        XCTAssertTrue(SweepNotice.all(for: [unreadable]).isEmpty)
    }

    // MARK: Helpers

    private func sweep(
        sampleID: String = "A12",
        bytes: Int64 = 0,
        panoramaProblem: String? = nil,
        stoppedEarly: Bool = false,
        counts: [String: Int]? = [:]
    ) -> SavedSweep {
        SavedSweep(
            url: URL(filePath: "/tmp/sweep-1"),
            manifest: SweepManifest(
                details: SampleDetails(
                    sampleID: sampleID,
                    location: "Tabanan",
                    field: 1,
                    moisture: .drained,
                    gramsOfSoil: 1,
                    millilitresScanned: nil,
                    recordedAt: .now
                ),
                frameCount: 12,
                byteCount: Int(bytes),
                stoppedEarly: stoppedEarly,
                panoramaFile: nil,
                panoramaProblem: panoramaProblem,
                organismCounts: counts
            ),
            recordedAt: .now,
            byteCount: bytes,
            frameURLs: [],
            panoramaURL: nil
        )
    }
}
