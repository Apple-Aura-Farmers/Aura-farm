import XCTest

@testable import AuraFarm

final class FileAdviceFeedbackStoreTests: XCTestCase {
    private let store = FileAdviceFeedbackStore()

    private func feedback(_ rating: AdviceFeedback.Rating, id: UUID = UUID()) -> AdviceFeedback {
        AdviceFeedback(
            id: id, givenAt: Date(timeIntervalSince1970: 1_800_000_000), rating: rating, reasons: [],
            source: .foundationModel,
            recommendation: Recommendation(
                summary: "Summary", noticed: [], steps: [], source: .foundationModel),
            contentVersion: "content-abc", appVersion: nil)
    }

    private func makeSweep() throws -> SavedSweep {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return SavedSweep(
            url: folder, manifest: nil, recordedAt: .now, byteCount: 0, frameURLs: [], panoramaURL: nil)
    }

    func testRecordAppends() throws {
        let sweep = try makeSweep()
        let first = feedback(.useful)
        let second = feedback(.notUseful)

        try store.record(first, for: sweep)
        try store.record(second, for: sweep)

        XCTAssertEqual(store.all(for: sweep), [first, second])
    }

    func testRecordReplacesAnEntryWithTheSameID() throws {
        let sweep = try makeSweep()
        let id = UUID()
        try store.record(feedback(.useful, id: id), for: sweep)
        try store.record(feedback(.notUseful), for: sweep)

        try store.record(feedback(.notUseful, id: id), for: sweep)

        let entries = store.all(for: sweep)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.rating, .notUseful)
    }

    func testAMissingFileReadsAsEmpty() throws {
        XCTAssertEqual(store.all(for: try makeSweep()), [])
    }

    func testACorruptFileReadsAsEmptyAndIsOverwrittenByTheNextRecord() throws {
        let sweep = try makeSweep()
        try Data("not json".utf8).write(to: sweep.url.appending(path: "advice-feedback.json"))
        XCTAssertEqual(store.all(for: sweep), [])

        let entry = feedback(.useful)
        try store.record(entry, for: sweep)

        XCTAssertEqual(store.all(for: sweep), [entry])
    }

    func testTheFileIsCalledAdviceFeedbackJSON() throws {
        let sweep = try makeSweep()

        try store.record(feedback(.useful), for: sweep)

        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: sweep.url.path), ["advice-feedback.json"])
    }

    func testFramesTheManifestAndTheAdviceFileAreUntouched() throws {
        let sweep = try makeSweep()
        let files = ["frame_01.jpg": "jpeg", "manifest.json": "{}", "advice.json": "[]"]
        for (name, text) in files { try Data(text.utf8).write(to: sweep.url.appending(path: name)) }

        try store.record(feedback(.useful), for: sweep)
        try store.record(feedback(.notUseful), for: sweep)

        for (name, text) in files {
            XCTAssertEqual(try Data(contentsOf: sweep.url.appending(path: name)), Data(text.utf8), name)
        }
        XCTAssertEqual(
            Set(try FileManager.default.contentsOfDirectory(atPath: sweep.url.path)),
            Set(files.keys).union(["advice-feedback.json"]))
    }

    func testTheSweepLibraryIgnoresTheFeedbackFile() throws {
        let sweep = try makeSweep()
        try Data("jpeg".utf8).write(to: sweep.url.appending(path: "frame_01.jpg"))
        try store.record(feedback(.useful), for: sweep)

        XCTAssertEqual(SweepLibrary.frameURLs(in: sweep.url).map(\.lastPathComponent), ["frame_01.jpg"])
    }
}
