import XCTest

@testable import MicroscopeCounter

final class ClipLibraryTests: XCTestCase {
    private var directory = URL(filePath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        directory = URL(filePath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func writeClip(sampleID: String, field: Int, secondsSinceEpoch: TimeInterval) throws {
        let metadata = RecordingMetadata(
            sampleID: sampleID,
            field: field,
            moisture: .flooded,
            gramsOfSoil: 10,
            millilitresScanned: 0.5,
            recordedAt: Date(timeIntervalSince1970: secondsSinceEpoch)
        )
        let clipURL = directory.appending(path: "\(metadata.fileBaseName).mov")
        try Data([0]).write(to: clipURL)
        try ClipRecorder.writeSidecar(metadata, forClipAt: clipURL)
    }

    func testListsClipsNewestFirstWithTheirDetails() throws {
        try writeClip(sampleID: "A12", field: 1, secondsSinceEpoch: 1_793_176_205)
        try writeClip(sampleID: "A12", field: 2, secondsSinceEpoch: 1_793_176_805)

        let clips = ClipLibrary.clips(in: directory)

        XCTAssertEqual(clips.count, 2)
        XCTAssertEqual(clips.map { $0.metadata?.field }, [2, 1])
        XCTAssertEqual(clips.first?.metadata?.sampleID, "A12")
        XCTAssertEqual(clips.first?.byteCount, 1)
    }

    func testClipWithoutASidecarIsStillListed() throws {
        try Data([0]).write(to: directory.appending(path: "orphan.mov"))

        let clips = ClipLibrary.clips(in: directory)

        XCTAssertEqual(clips.count, 1)
        XCTAssertNil(clips.first?.metadata)
    }

    func testSidecarsAndOtherFilesAreNotListedAsClips() throws {
        try writeClip(sampleID: "A12", field: 1, secondsSinceEpoch: 1_793_176_205)
        try Data([0]).write(to: directory.appending(path: "notes.txt"))

        XCTAssertEqual(ClipLibrary.clips(in: directory).count, 1)
    }

    func testMissingFolderGivesNoClips() {
        let missing = directory.appending(path: "nope", directoryHint: .isDirectory)
        XCTAssertTrue(ClipLibrary.clips(in: missing).isEmpty)
    }
}
