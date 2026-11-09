import AuraFarmKit
import Charts
import SwiftUI

/// Each nutrient's class over time, and the pH when it was measured, so a field drifting low
/// stands out.
struct NutrientTrendChart: View {
    /// In any order.
    let tests: [NutrientTest]

    private struct LevelPoint: Identifiable {
        var id: String
        var testedAt: Date
        var nutrient: String
        var rank: Int
    }

    private struct PHPoint: Identifiable {
        var id: Int
        var testedAt: Date
        var pH: Double
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NPK Over Time")
                .font(.headline)
            if tests.count < 2 {
                Text("The trend appears once two or more NPK results are added.")
                    .foregroundStyle(.secondary)
            } else {
                levelChart
                if phPoints.count >= 2 {
                    phChart
                }
            }
        }
    }

    private var levelChart: some View {
        Chart(levelPoints) { point in
            LineMark(
                x: .value("Tested", point.testedAt),
                y: .value("Class", point.rank)
            )
            .foregroundStyle(by: .value("Nutrient", point.nutrient))
            .symbol(by: .value("Nutrient", point.nutrient))
        }
        .chartYScale(domain: 0.5...3.5)
        .chartYAxis {
            AxisMarks(values: NutrientLevel.allCases.map(\.rank)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let rank = value.as(Int.self), let level = Self.level(ofRank: rank) {
                        Text(level.label)
                    }
                }
            }
        }
        .frame(height: 160)
    }

    private var phChart: some View {
        Chart(phPoints) { point in
            LineMark(
                x: .value("Tested", point.testedAt),
                y: .value("pH", point.pH)
            )
            PointMark(
                x: .value("Tested", point.testedAt),
                y: .value("pH", point.pH)
            )
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxisLabel("pH")
        .frame(height: 120)
    }

    /// Oldest first, so each line runs left to right.
    private var oldestFirst: [NutrientTest] {
        tests.sorted { $0.testedAt < $1.testedAt }
    }

    private var levelPoints: [LevelPoint] {
        oldestFirst.enumerated().flatMap { index, test in
            Nutrient.allCases.compactMap { nutrient in
                test.level(of: nutrient).map { level in
                    LevelPoint(
                        id: "\(index)-\(nutrient.rawValue)",
                        testedAt: test.testedAt,
                        nutrient: "\(nutrient.name) (\(nutrient.symbol))",
                        rank: level.rank
                    )
                }
            }
        }
    }

    private var phPoints: [PHPoint] {
        oldestFirst.enumerated().compactMap { index, test in
            test.pH.map { PHPoint(id: index, testedAt: test.testedAt, pH: $0) }
        }
    }

    private static func level(ofRank rank: Int) -> NutrientLevel? {
        NutrientLevel.allCases.first { $0.rank == rank }
    }
}
