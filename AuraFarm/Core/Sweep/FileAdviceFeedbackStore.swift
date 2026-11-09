import Foundation
import os

/// Keeps a sample's feedback in `advice-feedback.json` inside its sweep folder, as an array.
///
/// Frames, panoramas, `manifest.json` and `advice.json` are never touched. A file that can't
/// be read counts as empty and is overwritten by the next feedback.
struct FileAdviceFeedbackStore: AdviceFeedbackStore {
    static let fileName = "advice-feedback.json"

    func all(for sweep: SavedSweep) -> [AdviceFeedback] {
        guard let data = try? Data(contentsOf: Self.url(for: sweep)) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([AdviceFeedback].self, from: data)
        } catch {
            #if DEBUG
                Logger(subsystem: Bundle.main.bundleIdentifier ?? "AuraFarm", category: "advice")
                    .debug("Feedback could not be read: \(String(describing: error), privacy: .public)")
            #endif
            return []
        }
    }

    func record(_ feedback: AdviceFeedback, for sweep: SavedSweep) throws {
        var entries = all(for: sweep)
        if let index = entries.firstIndex(where: { $0.id == feedback.id }) {
            entries[index] = feedback
        } else {
            entries.append(feedback)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(entries).write(to: Self.url(for: sweep), options: .atomic)
    }

    private static func url(for sweep: SavedSweep) -> URL {
        sweep.url.appending(path: fileName)
    }
}
