import SwiftUI

/// The estimate: how much soil life was seen, the score, how sure it is, why, and when to
/// test again. Shown as one block so the band is never read without the rest.
struct SoilHealthCard: View {
    let estimate: SoilHealthEstimate

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: estimate.level.systemImage)
                    .font(.largeTitle)
                    .foregroundStyle(estimate.level.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(estimate.level.title)
                        .font(.title2.bold())
                    Text("Confidence: \(estimate.confidence.label)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let score = estimate.score {
                    Gauge(value: Double(score), in: 0...100) {
                        Text("Score")
                    } currentValueLabel: {
                        Text("\(score)")
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(estimate.level.tint)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(estimate.reasons, id: \.self) { reason in
                    Label(reason, systemImage: "circle.fill")
                        .labelStyle(BulletLabelStyle())
                }
            }
            .font(.callout)

            Label(estimate.followUp, systemImage: "calendar.badge.clock")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// A small dot in place of the icon, for short lists.
private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").foregroundStyle(.secondary)
            configuration.title
        }
    }
}

// MARK: - How each level looks

extension SoilHealthEstimate.Level {
    /// Says how much life was seen rather than judging the soil, so it can be read out.
    var title: String {
        switch self {
        case .good: return "Lots of soil life"
        case .fair: return "Some soil life"
        case .poor: return "Little soil life"
        case .tooFewToSay: return "Too few to say"
        case .notCounted: return "Not counted"
        }
    }

    var systemImage: String {
        switch self {
        case .good: return "leaf.fill"
        case .fair: return "leaf"
        case .poor: return "exclamationmark.triangle.fill"
        case .tooFewToSay: return "questionmark.circle.fill"
        case .notCounted: return "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .good: return .green
        case .fair: return .yellow
        case .poor: return .orange
        case .tooFewToSay, .notCounted: return .gray
        }
    }
}

extension SoilHealthEstimate.Confidence {
    var label: String { rawValue.capitalized }
}

#if DEBUG
    #Preview {
        List {
            ForEach(ResultScenario.allCases) { scenario in
                if let result = scenario.result {
                    SoilHealthCard(estimate: PlaceholderSoilHealthEstimator().estimate(result))
                }
            }
        }
    }
#endif
