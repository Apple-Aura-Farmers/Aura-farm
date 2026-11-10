import XCTest

@testable import AuraFarm

final class FileAdviceStoreTests: XCTestCase {
    private let store = FileAdviceStore()

    private let advice = SavedAdvice(
        recommendation: Recommendation(
            summary: "Some soil life was seen.", noticed: [],
            steps: [
                Recommendation.Step(actionID: .keepNotes, text: "Write it down.", why: "Why.", timing: "Now")
            ],
            source: .foundationModel),
        writtenAt: Date(timeIntervalSince1970: 1_800_000_000), contentVersion: AdviceContentVersion.current,
        appVersion: "1.0")

    private func makeSweep() throws -> SavedSweep {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return SavedSweep(
            url: folder, manifest: nil, recordedAt: .now, byteCount: 0, frameURLs: [], panoramaURL: nil)
    }

    func testSaveThenLoad() throws {
        let sweep = try makeSweep()

        try store.save(advice, for: sweep)

        XCTAssertEqual(store.load(for: sweep), advice)
    }

    func testAMissingFileLoadsAsNil() throws {
        XCTAssertNil(store.load(for: try makeSweep()))
    }

    func testACorruptFileLoadsAsNil() throws {
        let sweep = try makeSweep()
        try Data("not json".utf8).write(to: sweep.url.appending(path: "advice.json"))

        XCTAssertNil(store.load(for: sweep))
    }

    func testTheFileIsCalledAdviceJSON() throws {
        let sweep = try makeSweep()

        try store.save(advice, for: sweep)

        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: sweep.url.path), ["advice.json"])
    }

    func testFramesAndTheManifestAreUntouched() throws {
        let sweep = try makeSweep()
        let frame = sweep.url.appending(path: "frame_01.jpg")
        let manifest = sweep.url.appending(path: "manifest.json")
        try Data("jpeg".utf8).write(to: frame)
        try Data("{}".utf8).write(to: manifest)

        try store.save(advice, for: sweep)
        try store.save(advice, for: sweep)

        XCTAssertEqual(try Data(contentsOf: frame), Data("jpeg".utf8))
        XCTAssertEqual(try Data(contentsOf: manifest), Data("{}".utf8))
        XCTAssertEqual(
            Set(try FileManager.default.contentsOfDirectory(atPath: sweep.url.path)),
            ["frame_01.jpg", "manifest.json", "advice.json"])
    }

    func testTheSweepLibraryIgnoresTheAdviceFile() throws {
        let sweep = try makeSweep()
        try Data("jpeg".utf8).write(to: sweep.url.appending(path: "frame_01.jpg"))
        try store.save(advice, for: sweep)

        XCTAssertEqual(SweepLibrary.frameURLs(in: sweep.url).map(\.lastPathComponent), ["frame_01.jpg"])
    }
}
