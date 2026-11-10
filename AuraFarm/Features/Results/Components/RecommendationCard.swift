import SwiftUI

/// What to do next: a spinner while it is written, the advice, or a way to try again.
struct RecommendationCard: View {
    let state: RecommendationState
    /// Why the fixed advice is shown instead of the model's, if it is.
    let modelUnavailableReason: String?
    let onRetry: () -> Void

    var body: some View {
        switch state {
        case .idle, .generating:
            HStack(spacing: 12) {
                ProgressView()
                Text("Writing advice for this sample…")
                    .foregroundStyle(.secondary)
            }
        case .ready(let recommendation):
            VStack(alignment: .leading, spacing: 10) {
                Text(recommendation.summary)
                    .font(.body.weight(.semibold))
                ForEach(Array(recommendation.actions.enumerated()), id: \.offset) { index, action in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(action)
                    }
                }
                SourceTag(source: recommendation.source)
                if let modelUnavailableReason {
                    Text(modelUnavailableReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.bubble")
                    .foregroundStyle(.secondary)
                Button("Try again", action: onRetry)
            }
        }
    }
}

/// Says where the advice came from, so generated text is never mistaken for an expert's.
private struct SourceTag: View {
    let source: Recommendation.Source

    var body: some View {
        Label(text, systemImage: image)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.fill.tertiary, in: Capsule())
            .foregroundStyle(.secondary)
    }

    private var text: String {
        switch source {
        case .foundationModel: return "Written by Apple Intelligence"
        case .rules: return "Standard advice"
        }
    }

    private var image: String {
        switch source {
        case .foundationModel: return "apple.intelligence"
        case .rules: return "list.bullet.clipboard"
        }
    }
}

#Preview {
    List {
        RecommendationCard(state: .generating, modelUnavailableReason: nil) {}
        RecommendationCard(
            state: .ready(RuleBasedRecommender.recommendation(for: .fair)),
            modelUnavailableReason: "Apple Intelligence is turned off in Settings."
        ) {}
        RecommendationCard(state: .failed(message: "The advice could not be written. Try again.")) {}
    }
}

extension RecommendationCard {
    /// For previews and a failed state, where no fallback reason applies.
    init(state: RecommendationState, onRetry: @escaping () -> Void) {
        self.init(state: state, modelUnavailableReason: nil, onRetry: onRetry)
    }
}
