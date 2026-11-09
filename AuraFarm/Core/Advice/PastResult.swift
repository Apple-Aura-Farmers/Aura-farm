import Foundation

/// An earlier sample of the same plot, cut down to what the advice compares.
///
/// Built from the advice content in `docs/advice-content.md` (the team's "Advice content,
/// Phase 1", approved 9 November 2026). Change the content in both places.
///
/// PROVISIONAL: not checked by an agronomist.
struct PastResult: Equatable {
    var recordedAt: Date
    var moisture: SampleDetails.Moisture
    var cropStage: SampleDetails.CropStage?
    /// Interpreted organisms only, per kept frame.
    var organismsPerFrame: Double
    /// Kinds of interpreted organism counted at least once.
    var interpretedKinds: Int
    var level: SoilHealthEstimate.Level
}

extension PastResult {
    init(_ result: SoilResult, level: SoilHealthEstimate.Level) {
        var kinds = Set<String>()
        var total = 0
        for (label, count) in result.countsByClass ?? [:] where count > 0 {
            guard let note = OrganismNotes.note(forLabel: label), note.use == .interpreted else { continue }
            kinds.insert(note.label)
            total += count
        }
        self.init(
            recordedAt: result.recordedAt,
            moisture: result.moisture,
            cropStage: result.cropStage,
            organismsPerFrame: Double(total) / Double(max(result.framesKept, 1)),
            interpretedKinds: kinds.count,
            level: level
        )
    }
}
