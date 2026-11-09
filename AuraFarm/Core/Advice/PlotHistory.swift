import Foundation

/// Finds earlier samples of the same farm plot, so the advice can mention a change.
///
/// Part of the advice built from `docs/advice-content.md` (the team's "Advice content,
/// Phase 1", approved 9 November 2026). Change the content in both places.
///
/// PROVISIONAL: not checked by an agronomist.
enum PlotHistory {
    /// Earlier counted samples of the result's plot, newest first. Pure: works over the
    /// sweeps it is given and never reads the disk, so the caller passes
    /// `SweepLibrary.sweeps()`.
    static func earlierResults(
        for result: SoilResult,
        among sweeps: [SavedSweep],
        estimator: some SoilHealthEstimating = PlaceholderSoilHealthEstimator(),
        limit: Int = 3
    ) -> [PastResult] {
        guard let plot = key(result.plotName) else { return [] }
        return
            sweeps
            .filter { $0.id != result.sweep?.id }
            .compactMap { sweep -> SoilResult? in
                guard sweep.manifest?.organismCounts != nil else { return nil }
                return try? SoilResult(sweep: sweep)
            }
            .filter { key($0.plotName) == plot && $0.recordedAt < result.recordedAt }
            .sorted { $0.recordedAt > $1.recordedAt }
            .prefix(max(limit, 0))
            .map { PastResult($0, level: estimator.estimate($0).level) }
    }

    /// A plot name as it is matched: trimmed, any case. nil when blank.
    private static func key(_ name: String?) -> String? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
