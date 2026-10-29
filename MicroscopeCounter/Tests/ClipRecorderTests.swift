import XCTest
@testable import MicroscopeCounter

final class ClipRecorderTests: XCTestCase {
    private var directory = URL(filePath: NSTemporaryDirectory())

    private func metadata(sampleID: String = "A12", field: Int = 3) -> RecordingMetadata {
        RecordingMetadata(
            sampleID: sampleID,
            field: field,
            moisture: .drained,
            gramsOfSoil: 10,
            millilitresScanned: 0.5,
            // 2026-10-28T08:30:05Z
            recordedAt: Date(timeIntervalSince1970: 1_793_176_205)
        )
    }

    override func setUpWithError() throws {
        directory = URL(filePath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testFileBaseNameUsesSampleFieldAndTime() {
        XCTAssertEqual(metadata().fileBaseName, "A12_f003_20261028-083005")
    }

    func testFileBaseNameDropsCharactersThatBreakFileNames() {
        XCTAssertEqual(metadata(sampleID: "A 12/B").fileBaseName, "A-12-B_f003_20261028-083005")
    }

    func testIncompleteDetailsAreRejected() {
        var details = metadata()
        XCTAssertTrue(details.isComplete)
        details.sampleID = "  "
        XCTAssertFalse(details.isComplete)
        details.sampleID = "A12"
        details.millilitresScanned = 0
        XCTAssertFalse(details.isComplete)
        details.millilitresScanned = 0.5
        details.gramsOfSoil = nil
        XCTAssertFalse(details.isComplete)
    }

    func testFreeURLNeverReusesAnExistingClip() throws {
        let first = ClipRecorder.freeURL(base: "A12_f003", extension: "mov", in: directory)
        try Data().write(to: first)
        let second = ClipRecorder.freeURL(base: "A12_f003", extension: "mov", in: directory)

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(second.lastPathComponent, "A12_f003-2.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
    }

    func testSidecarSitsBesideTheClipAndRoundTrips() throws {
        let clipURL = directory.appending(path: "A12_f003.mov")
        try ClipRecorder.writeSidecar(metadata(), forClipAt: clipURL)

        let sidecarURL = directory.appending(path: "A12_f003.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RecordingMetadata.self, from: Data(contentsOf: sidecarURL))

        XCTAssertEqual(decoded, metadata())
    }
}
