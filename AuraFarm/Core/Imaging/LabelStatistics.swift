import Foundation

/// How brightness-independent measures spread per label (measured inside the registration box), so the team can see whether sample,
/// blank glass and blur separate.
struct LabelStatistics {
    struct Spread: Equatable {
        var p10: Double
        var median: Double
        var p90: Double
    }

    struct Summary: Equatable {
        var label: String
        var count: Int
        var contrast: Spread
        var sharpness: Spread
    }

    /// One summary per non-empty label, in the order sample, blank, blurry. Rows with any
    /// other label (including none) are left out.
    static func summaries(of rows: [MovementLogRow]) -> [Summary] {
        ["sample", "blank", "blurry"].compactMap { label in
            let matching = rows.filter { $0.label == label }
            guard !matching.isEmpty else { return nil }
            return Summary(
                label: label, count: matching.count,
                contrast: spread(matching.map(\.boxContrast)),
                sharpness: spread(matching.map(\.boxSharpness)))
        }
    }

    private static func spread(_ values: [Double]) -> Spread {
        let sorted = values.sorted()
        return Spread(
            p10: nearestRank(sorted, 0.10), median: nearestRank(sorted, 0.50),
            p90: nearestRank(sorted, 0.90))
    }

    /// Nearest-rank percentile of already sorted, non-empty values.
    private static func nearestRank(_ sorted: [Double], _ fraction: Double) -> Double {
        let rank = Int((fraction * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }
}
