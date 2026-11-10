import Foundation

/// Keeps a sample's feedback in `advice-feedback.json` inside its sweep folder, as an array.
///
/// Frames, panoramas, `manifest.json` and `advice.json` are never touched. A file that can't
/// be read counts as empty and is overwritten by the next feedback.
struct FileAdviceFeedbackStore: AdviceFeedbackStore {
    static let fileName = "advice-feedback.json"

    func all(for sweep: SavedSweep) -> [AdviceFeedback] {
        SweepJSONFile.read([AdviceFeedback].self, named: Self.fileName, in: sweep, what: "Feedback") ?? []
    }

    func record(_ feedback: AdviceFeedback, for sweep: SavedSweep) throws {
        var entries = all(for: sweep)
        if let index = entries.firstIndex(where: { $0.id == feedback.id }) {
            entries[index] = feedback
        } else {
            entries.append(feedback)
        }
        try SweepJSONFile.write(entries, named: Self.fileName, in: sweep)
    }
}
