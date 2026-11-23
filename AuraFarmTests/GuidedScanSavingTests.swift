import XCTest

@testable import AuraFarm

final class GuidedScanSavingTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(
            path: "guided-scan-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var details: SampleDetails {
        SampleDetails(
            sampleID: "Pak Wayan", location: "Tabanan", field: 1, moisture: .drained,
            gramsOfSoil: 10, millilitresScanned: nil,
            recordedAt: Date(timeIntervalSince1970: 1_793_176_205))
    }

    private var record: GuideRunRecord {
        var record = GuideRunRecord.previewForTests
        record.countsByLabel = ["Volvox": 3, "Nematode": 2]
        record.totalCount = 5
        record.detectorModel = DetectorModel.v3.rawValue
        return record
    }

    private func savedSweep(csv: URL? = nil) throws -> SavedSweep {
        let name = try GuidedScanSaver.save(
            details: details, record: record, movementCSV: csv, in: directory)
        return try XCTUnwrap(SweepLibrary.sweeps(in: directory).first { $0.name == name })
    }

    func testAGuidedScanSavesWithNoFramesAndItsCounts() throws {
        let sweep = try savedSweep()
        let manifest = try XCTUnwrap(sweep.manifest)
        XCTAssertEqual(manifest.frameCount, 0)
        XCTAssertEqual(manifest.guidedScan, true)
        XCTAssertEqual(manifest.organismCounts, ["Volvox": 3, "Nematode": 2])
        XCTAssertEqual(manifest.totalOrganismCount, 5)
        XCTAssertNil(manifest.panoramaFile)
        XCTAssertFalse(manifest.stoppedEarly)
        XCTAssertEqual(manifest.details, details)
        XCTAssertTrue(sweep.frameURLs.isEmpty)
    }

    /// A record with three organisms, and a run folder with the pictures of the first two.
    private func runWithPictures(in runs: URL) throws -> (record: GuideRunRecord, folder: URL) {
        var record = record
        record.organisms = (1...3).map {
            RunMapOrganism(
                label: $0 == 2 ? "Nematode" : "Volvox", x: 0, y: 0, column: 1, seconds: 1,
                image: "organism-00\($0).jpg")
        }
        let folder = runs.appending(path: "run-20261123-100000-organisms")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for i in 1...2 {
            try Data("picture \(i)".utf8).write(to: folder.appending(path: "organism-00\(i).jpg"))
        }
        return (record, folder)
    }

    func testTheOrganismPicturesAreKeptWithTheSweepAndNamedInItsReport() throws {
        let runs = directory.appending(path: "elsewhere-runs")
        let (record, folder) = try runWithPictures(in: runs)
        let sweeps = directory.appending(path: "sweeps")
        let name = try GuidedScanSaver.save(
            details: details, record: record, movementCSV: nil, organisms: folder, in: sweeps)
        // The run's own folder may go: the sweep keeps its pictures.
        try FileManager.default.removeItem(at: runs)
        let sweep = try XCTUnwrap(SweepLibrary.sweeps(in: sweeps).first { $0.name == name })
        XCTAssertTrue(sweep.frameURLs.isEmpty, "pictures are not frames")

        let pictures = OrganismPictures.of(sweep, runs: runs)
        let id = SoilReportExporter.reportID(for: sweep).uuidString.lowercased()
        XCTAssertEqual(
            pictures.map(\.image),
            [
                .init(taxon: "Volvox", path: "\(id)/organism-001.jpg"),
                .init(taxon: "Nematode", path: "\(id)/organism-002.jpg"),
            ], "the third organism has no picture on the phone")
        XCTAssertEqual(try pictures.map { try Data(contentsOf: $0.file) }.first, Data("picture 1".utf8))
        XCTAssertEqual(
            try SoilReportExporter.report(for: sweep).organismImages, pictures.map(\.image))
        XCTAssertNil(try XCTUnwrap(GuidedScanSaver.runRecord(in: sweep.url)).organisms[2].image)
    }

    func testASweepSavedBeforeItKeptItsPicturesFindsThoseOfItsRun() throws {
        let runs = directory.appending(path: "elsewhere-runs")
        let (record, folder) = try runWithPictures(in: runs)
        try GuideRunRecord.encoder().encode(record).write(
            to: runs.appending(path: "run-20261123-100000.json"))
        var other = record
        other.started = record.started.addingTimeInterval(-900)
        try GuideRunRecord.encoder().encode(other).write(
            to: runs.appending(path: "run-20261123-094500.json"))
        let sweeps = directory.appending(path: "sweeps")
        let name = try GuidedScanSaver.save(
            details: details, record: record, movementCSV: nil, in: sweeps)
        let sweep = try XCTUnwrap(SweepLibrary.sweeps(in: sweeps).first { $0.name == name })
        XCTAssertEqual(
            OrganismPictures.of(sweep, runs: runs).map(\.file.path),
            ["organism-001.jpg", "organism-002.jpg"].map { folder.appending(path: $0).path })
    }

    func testASweepWithNoPicturesSendsNone() throws {
        let sweep = try savedSweep()
        XCTAssertTrue(OrganismPictures.of(sweep, runs: directory.appending(path: "none")).isEmpty)
        XCTAssertNil(try SoilReportExporter.report(for: sweep).organismImages)
    }

    func testTheLensVideoIsLinkedIntoTheSweepAndNamedInItsRecord() throws {
        let video = directory.appending(path: "lens-test.mov")
        try Data("video".utf8).write(to: video)
        var withVideo = record
        withVideo.lensVideoFile = "lens-test.mov"
        withVideo.lensVideoScanStartSeconds = 12
        let name = try GuidedScanSaver.save(
            details: details, record: withVideo, movementCSV: nil, lensVideo: video, in: directory)
        let folder = directory.appending(path: name)
        XCTAssertEqual(try Data(contentsOf: folder.appending(path: "lens-test.mov")), Data("video".utf8))
        XCTAssertEqual(GuidedScanSaver.runRecord(in: folder)?.lensVideoFile, "lens-test.mov")
        XCTAssertEqual(GuidedScanSaver.runRecord(in: folder)?.lensVideoScanStartSeconds, 12)
    }

    func testAVideoThatCannotBeKeptIsNotNamedInTheRecord() throws {
        var withVideo = record
        withVideo.lensVideoFile = "lens-gone.mov"
        withVideo.lensVideoScanStartSeconds = 12
        let name = try GuidedScanSaver.save(
            details: details, record: withVideo, movementCSV: nil,
            lensVideo: directory.appending(path: "missing.mov"), in: directory)
        let saved = GuidedScanSaver.runRecord(in: directory.appending(path: name))
        XCTAssertNil(saved?.lensVideoFile)
        XCTAssertNil(saved?.lensVideoScanStartSeconds)
    }

    func testItNeverReportsNoFramesWereKept() throws {
        // The failure belongs to the frame recorder (the stitch tool's), which this path does not use; the
        // result screen reads the sweep without any failure.
        let sweep = try savedSweep()
        XCTAssertNoThrow(try SoilResult(sweep: sweep))
        XCTAssertEqual(try SoilResult(sweep: sweep).totalCount, 5)
        XCTAssertTrue(SweepNotice.all(for: [sweep]).isEmpty, "no notice about the sweep either")
    }

    func testTheFolderHoldsTheRunRecordAndTheCSV() throws {
        let csv = directory.appending(path: "source.csv")
        try "seconds\n0\n".write(to: csv, atomically: true, encoding: .utf8)
        let sweep = try savedSweep(csv: csv)
        let fileNames = try FileManager.default.contentsOfDirectory(atPath: sweep.url.path)
        XCTAssertTrue(fileNames.contains(GuidedScanSaver.runRecordFileName))
        XCTAssertTrue(fileNames.contains(GuidedScanSaver.movementFileName))
        XCTAssertTrue(fileNames.contains("manifest.json"))
        XCTAssertEqual(GuidedScanSaver.runRecord(in: sweep.url), record)
    }

    func testASweepFromTheCaptureScreenHasNoRunRecord() throws {
        let folder = directory.appending(path: "plain")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertNil(GuidedScanSaver.runRecord(in: folder))
    }

    func testAGuidedScanBuildsASoilReportWithZeroFramesAndTheV2Model() throws {
        let sweep = try savedSweep()
        let report = try SoilReportExporter.report(for: sweep)
        XCTAssertEqual(report.capture.frameCount, 0)
        XCTAssertEqual(report.capture.detectorModel, "SoilDetectorV3")
        XCTAssertNil(report.panoramaJPEG)
        XCTAssertEqual(report.organisms.map(\.taxon), ["Volvox", "Nematode"])
        XCTAssertEqual(report.organisms.map(\.count), [3, 2])
        XCTAssertEqual(report.sample.sampleID, "Pak Wayan")
    }

    func testTwoScansOfOneSampleNeverShareAFolder() throws {
        let first = try savedSweep()
        let second = try savedSweep()
        XCTAssertNotEqual(first.url, second.url)
    }

    #if DEBUG
        // MARK: The existing zero-frame failure

        func testTheFrameRecorderStillFailsAZeroFrameSweep() {
            let recorder = SweepRecorder()
            XCTAssertTrue(recorder.begin(details: details))
            let finished = recorder.finish(stoppedEarly: false)
            XCTAssertNotNil(finished)
            let expectation = expectation(description: "published")
            DispatchQueue.main.async { expectation.fulfill() }
            wait(for: [expectation], timeout: 2)
            XCTAssertEqual(recorder.errorMessage, "No frames were kept. Check the image and try again.")
        }
    #endif

    // MARK: The results screen's map

    func testTheSwitchesChangeWhatTheMapDraws() throws {
        var content = RunMapContent(record: .previewForTests)
        XCTAssertFalse(content.drawnPath.isEmpty)
        XCTAssertFalse(content.drawnEdges.isEmpty)
        XCTAssertFalse(content.drawnOrganisms.isEmpty)
        let framed = content.screenBounds

        content.layers.path = false
        XCTAssertTrue(content.drawnPath.isEmpty)
        XCTAssertFalse(content.drawnEdges.isEmpty)
        content.layers.edges = false
        XCTAssertTrue(content.drawnEdges.isEmpty)
        content.layers.organisms = false
        XCTAssertTrue(content.drawnOrganisms.isEmpty)
        XCTAssertEqual(content.screenBounds, framed, "the map does not jump when a layer goes")
    }

    func testTappingALegendRowShowsOnlyThatType() {
        var content = RunMapContent(record: .previewForTests)
        let all = content.drawnOrganisms.count
        content.layers.onlyType = "Volvox"
        XCTAssertFalse(content.drawnOrganisms.isEmpty)
        XCTAssertLessThan(content.drawnOrganisms.count, all)
        XCTAssertTrue(content.drawnOrganisms.allSatisfy { $0.label == "Volvox" })
        content.layers.organisms = false
        XCTAssertTrue(content.drawnOrganisms.isEmpty, "the Organisms switch still wins")
    }
}

extension GuideRunRecord {
    /// A small record for tests: a path, two edges and organisms of two types.
    static var previewForTests: GuideRunRecord {
        var record = GuideRunRecord(
            started: Date(timeIntervalSince1970: 1_700_000_000),
            ended: Date(timeIntervalSince1970: 1_700_000_300), finishReason: .rightEdge,
            spotMode: "brief_touch", coverageStep: 1.6, columns: 3, spotsTicked: 20, missedSpots: 0,
            elapsedSeconds: 300, secondsPerSpot: 15, coverageShare: 0.5, countsByLabel: [:],
            tallyCountsByLabel: [:], totalCount: 0, minimumConfidence: 0.3, cropToEyepiece: true,
            classNames: ["Volvox", "Nematode"], framesCounted: 100, framesSkippedByReason: [:])
        record.path = (0..<20).map { RunMapPoint(x: Double($0) / 4, y: 2 + sin(Double($0))) }
        record.edges = [
            RunMapEdge(kind: "top", x1: 0, y1: 0, x2: 5, y2: 0),
            RunMapEdge(kind: "bottom", x1: 0, y1: 4, x2: 5, y2: 4),
        ]
        record.organisms = (0..<6).map {
            RunMapOrganism(
                label: $0 < 3 ? "Volvox" : "Nematode", x: Double($0), y: 1.5, column: 1,
                seconds: Double($0))
        }
        return record
    }
}
