import Foundation
import os

/// Keeps a sample's advice in `advice.json` inside its sweep folder.
///
/// `advice.json` is the only file the app writes into a sweep folder after recording; the
/// frames, panoramas and `manifest.json` are never touched. The advice is not part of the soil
/// report sent to the Mac.
struct FileAdviceStore: AdviceStore {
    static let fileName = "advice.json"

    func load(for sweep: SavedSweep) -> SavedAdvice? {
        guard let data = try? Data(contentsOf: Self.url(for: sweep)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(SavedAdvice.self, from: data)
        } catch {
            #if DEBUG
                Logger(subsystem: Bundle.main.bundleIdentifier ?? "AuraFarm", category: "advice")
                    .debug("Saved advice could not be read: \(String(describing: error), privacy: .public)")
            #endif
            return nil
        }
    }

    func save(_ advice: SavedAdvice, for sweep: SavedSweep) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(advice).write(to: Self.url(for: sweep), options: .atomic)
    }

    private static func url(for sweep: SavedSweep) -> URL {
        sweep.url.appending(path: fileName)
    }
}
