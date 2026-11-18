import Foundation

/// The rows of the legend under the run map: only the types present, most first.
enum LifeLegend {
    struct Row: Equatable, Identifiable {
        var label: String
        var count: Int
        var id: String { label }
        /// What is shown on screen; `label` stays the data.
        var display: String { OrganismDisplayName.label(label) }
    }

    /// The rows for `counts` (label -> helper count), biggest first, ties by label. With `limit`,
    /// only that many rows and how many were left out ("+N more").
    static func rows(counts: [String: Int], limit: Int? = nil) -> (rows: [Row], more: Int) {
        let all = counts.filter { $0.value > 0 }
            .map { Row(label: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.label < $1.label }
        guard let limit, all.count > limit else { return (all, 0) }
        return (Array(all.prefix(limit)), all.count - limit)
    }
}
