import XCTest

@testable import MicroscopeCounter

final class FrameSetLibraryTests: XCTestCase {
    func testSweepsAreListedNewestFirstWithTheirDetails() throws {
        let root = try makeTemporaryDirectory()
        try makeSweep(
            in: root, named: "A12_f001", frames: 2,
            manifest: manifest(sampleID: "A12", field: 1, at: Date(timeIntervalSince1970: 1_000)))
        try makeSweep(
            in: root, named: "A12_f002", frames: 3,
            manifest: manifest(sampleID: "A12", field: 2, at: Date(timeIntervalSince1970: 2_000)))

        let sets = FrameSetLibrary.frameSets(in: root)

        XCTAssertEqual(sets.count, 2)
        XCTAssertEqual(sets.first?.manifest?.details.field, 2)
        XCTAssertEqual(sets.first?.frameCount, 3)
        XCTAssertEqual(sets.last?.manifest?.details.field, 1)
        XCTAssertEqual(sets.last?.frameCount, 2)
    }

    func testASweepWithNoManifestIsStillListed() throws {
        let root = try makeTemporaryDirectory()
        try makeSweep(in: root, named: "orphan", frames: 1, manifest: nil)

        let sets = FrameSetLibrary.frameSets(in: root)

        XCTAssertEqual(sets.count, 1)
        XCTAssertNil(sets.first?.manifest)
        XCTAssertEqual(sets.first?.name, "orphan")
        XCTAssertEqual(sets.first?.frameCount, 1)
    }

    func testFilesThatAreNotFramesAreIgnored() throws {
        let root = try makeTemporaryDirectory()
        try makeSweep(in: root, named: "A12_f001", frames: 1, manifest: nil)
        try Data("notes".utf8).write(to: root.appending(path: "A12_f001/notes.txt"))
        // A loose file beside the folders is not a sweep.
        try Data("stray".utf8).write(to: root.appending(path: "stray.jpg"))

        let sets = FrameSetLibrary.frameSets(in: root)

        XCTAssertEqual(sets.count, 1)
        XCTAssertEqual(sets.first?.frameCount, 1)
    }

    func testAMissingFolderListsNothing() {
        let missing = URL.temporaryDirectory.appending(path: UUID().uuidString)
        XCTAssertTrue(FrameSetLibrary.frameSets(in: missing).isEmpty)
        XCTAssertEqual(FrameSetLibrary.totalBytes(in: missing), 0)
    }

    func testTotalBytesAddsUpEverySweep() throws {
        let root = try makeTemporaryDirectory()
        try makeSweep(in: root, named: "A12_f001", frames: 2, manifest: nil)
        try makeSweep(in: root, named: "A12_f002", frames: 1, manifest: nil)

        // Each stub frame is 4 bytes.
        XCTAssertEqual(FrameSetLibrary.totalBytes(in: root), 12)
    }

    // MARK: Helpers

    private func manifest(sampleID: String, field: Int, at date: Date) -> FrameSetManifest {
        FrameSetManifest(
            details: RecordingMetadata(
                sampleID: sampleID,
                field: field,
                moisture: .flooded,
                gramsOfSoil: 10,
                millilitresScanned: 0.5,
                recordedAt: date
            ),
            frameCount: 0,
            byteCount: 0,
            stoppedEarly: false
        )
    }

    private func makeSweep(
        in root: URL, named name: String, frames: Int, manifest: FrameSetManifest?
    ) throws {
        let folder = root.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 1...max(frames, 1) where frames > 0 {
            try Data("jpeg".utf8).write(
                to: folder.appending(path: String(format: "frame_%02d.jpg", index)))
        }
        if let manifest {
            try FrameSetRecorder.writeManifest(manifest, inFrameSetAt: folder)
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
