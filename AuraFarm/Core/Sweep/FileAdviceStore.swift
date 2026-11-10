import Foundation

/// Keeps a sample's advice in `advice.json` inside its sweep folder.
///
/// `advice.json` is the only file the app writes into a sweep folder after recording; the
/// frames, panoramas and `manifest.json` are never touched. The advice is not part of the soil
/// report sent to the Mac.
struct FileAdviceStore: AdviceStore {
    static let fileName = "advice.json"

    func load(for sweep: SavedSweep) -> SavedAdvice? {
        SweepJSONFile.read(SavedAdvice.self, named: Self.fileName, in: sweep, what: "Saved advice")
    }

    func save(_ advice: SavedAdvice, for sweep: SavedSweep) throws {
        try SweepJSONFile.write(advice, named: Self.fileName, in: sweep)
    }
}
