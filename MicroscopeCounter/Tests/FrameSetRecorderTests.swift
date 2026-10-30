import XCTest

@testable import MicroscopeCounter

final class FrameSetRecorderTests: XCTestCase {
    /// 2026-10-28 08:30:05 UTC, so the expected stamp does not depend on the test machine.
    private let fixedDate = Date(timeIntervalSince1970: 1_793_176_205)

    private func details(sampleID: String = "A12", field: Int = 3) -> RecordingMetadata {
        RecordingMetadata(
            sampleID: sampleID,
            field: field,
            moisture: .drained,
            gramsOfSoil: 10,
            millilitresScanned: 0.5,
            recordedAt: fixedDate
        )
    }

    func testFolderNameUsesSampleFieldAndTime() {
        XCTAssertEqual(details().fileBaseName, "A12_f003_20261028-083005")
    }

    func testFolderNameReplacesCharactersThatAreUnsafeInAFileName() {
        XCTAssertEqual(
            details(sampleID: "A 12/B", field: 1).fileBaseName,
            "A-12-B_f001_20261028-083005"
        )
    }

    func testIncompleteDetailsAreRejected() {
        var incomplete = details()
        incomplete.gramsOfSoil = nil
        XCTAssertFalse(incomplete.isComplete)

        incomplete.gramsOfSoil = 10
        incomplete.millilitresScanned = nil
        XCTAssertFalse(incomplete.isComplete)

        incomplete.millilitresScanned = 0.5
        incomplete.sampleID = "   "
        XCTAssertFalse(incomplete.isComplete)

        XCTAssertTrue(details().isComplete)
    }

    func testFreeURLNeverWritesIntoAnExistingSweep() throws {
        let directory = try makeTemporaryDirectory()
        let first = FrameSetRecorder.freeURL(base: "A12_f001", in: directory)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)

        let second = FrameSetRecorder.freeURL(base: "A12_f001", in: directory)

        XCTAssertEqual(first.lastPathComponent, "A12_f001")
        XCTAssertEqual(second.lastPathComponent, "A12_f001-2")
        XCTAssertNotEqual(first, second)
    }

    func testManifestSitsInTheSweepFolderAndRoundTrips() throws {
        let folder = try makeTemporaryDirectory()
        let manifest = FrameSetManifest(
            details: details(), frameCount: 7, byteCount: 2_048, stoppedEarly: true)

        try FrameSetRecorder.writeManifest(manifest, inFrameSetAt: folder)

        let url = folder.appending(path: "manifest.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FrameSetManifest.self, from: Data(contentsOf: url))

        XCTAssertEqual(decoded.frameCount, 7)
        XCTAssertEqual(decoded.byteCount, 2_048)
        XCTAssertTrue(decoded.stoppedEarly)
        XCTAssertEqual(decoded.details.sampleID, "A12")
        XCTAssertEqual(decoded.details.field, 3)
        XCTAssertEqual(decoded.details.recordedAt.timeIntervalSince1970, fixedDate.timeIntervalSince1970)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
