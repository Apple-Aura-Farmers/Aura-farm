import SwiftUI

/// What to do next: a spinner while it is written, the advice, or a way to try again.
struct RecommendationCard: View {
    let state: RecommendationState
    /// Why the fixed advice is shown instead of the model's, if it is.
    let modelUnavailableReason: String?
    /// Where the model has got to while it writes, if it has said.
    var progress: AdviceProgress?
    /// What the advice used, in one line.
    var basis: String?
    /// Why the advice was just written again, such as "Updated with the new pH reading."
    var updateNote: String?
    /// When the advice on screen was saved with the sample, if it was.
    var savedAt: Date?
    /// True when the saved advice was written with older advice rules.
    var savedFromOlderRules = false
    /// What the helper rated the advice, if they did.
    var rating: AdviceFeedback.Rating?
    /// Called with a rating, and the reasons when it is not useful. nil hides the question.
    var onRate: ((AdviceFeedback.Rating, [AdviceFeedback.Reason]) -> Void)?
    let onRetry: () -> Void

    @State private var asksWhatWasWrong = false

    var body: some View {
        switch state {
        case .idle, .generating:
            HStack(spacing: 12) {
                ProgressView()
                Text(progress?.message ?? "Writing advice for this sample…")
                    .foregroundStyle(.secondary)
            }
        case .ready(let recommendation):
            VStack(alignment: .leading, spacing: 10) {
                Text(recommendation.summary)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if !recommendation.noticed.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("What stood out")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(recommendation.noticed, id: \.self) { point in
                            Text(point)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                ForEach(Array(recommendation.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.text)
                                .fixedSize(horizontal: false, vertical: true)
                            if let why = step.why {
                                Text(why)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let timing = step.timing {
                                Label(timing, systemImage: "clock")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                SourceTag(source: recommendation.source)
                if let basis {
                    Text(basis)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let updateNote {
                    Label(updateNote, systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let savedAt {
                    Text("Written \(savedAt.formatted(date: .abbreviated, time: .shortened)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if savedFromOlderRules {
                    Text(
                        "Written with older advice rules. Tap Write again for advice with the current rules."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                if let modelUnavailableReason {
                    Text(modelUnavailableReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let onRate {
                    feedbackRow(onRate)
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

extension RecommendationCard {
    /// "Was this useful?" with a thumb up and a thumb down. A thumb down asks what was wrong.
    fileprivate func feedbackRow(
        _ onRate: @escaping (AdviceFeedback.Rating, [AdviceFeedback.Reason]) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 16) {
                Text("Was this useful?")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    onRate(.useful, [])
                } label: {
                    Image(systemName: rating == .useful ? "hand.thumbsup.fill" : "hand.thumbsup")
                }
                .accessibilityLabel("Useful")
                Button {
                    asksWhatWasWrong = true
                } label: {
                    Image(systemName: rating == .notUseful ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                }
                .accessibilityLabel("Not useful")
            }
            .buttonStyle(.borderless)
            if rating != nil {
                Text("Thanks, saved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("What was wrong?", isPresented: $asksWhatWasWrong, titleVisibility: .visible) {
            ForEach(AdviceFeedback.Reason.allCases, id: \.self) { reason in
                Button(reason.label) { onRate(.notUseful, [reason]) }
            }
            Button("Cancel", role: .cancel) {}
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
    let model = Recommendation(
        summary: "Plenty is living in this soil, with signs the water may be rich in nutrients.",
        noticed: ["Many Euglena, which can mean still, nutrient-rich water."],
        steps: [
            Recommendation.Step(
                actionID: .refreshWater,
                text: "Try not to let water sit still for long. Let fresh water flow in where you can.",
                why: "Lots of Euglena often goes with still water.", timing: "This week"),
            Recommendation.Step(
                actionID: .keepNotes,
                text: "Write down what you did in this field, so the next sample can be compared fairly.",
                why: "So the next sample can show a change.", timing: "Now"),
        ],
        source: .foundationModel)
    let rules = Recommendation(
        summary: "Some soil life was seen. Small changes may help it grow.",
        noticed: [],
        steps: [
            Recommendation.Step(
                actionID: .resampleLater,
                text: "Sample this field again in 2 to 4 weeks, the same way, to see if it changes.",
                why: nil, timing: "2 to 4 weeks"),
            Recommendation.Step(
                actionID: .keepNotes,
                text: "Write down what you did in this field, so the next sample can be compared fairly.",
                why: nil, timing: "Now"),
        ],
        source: .rules)
    List {
        RecommendationCard(
            state: .ready(model), modelUnavailableReason: nil,
            basis:
                "Based on 41 organisms (3 kinds) in 12 frames, flooded, tillering. 10 others weren't used.",
            onRate: { _, _ in }
        ) {}
        RecommendationCard(
            state: .ready(model), modelUnavailableReason: nil,
            basis: "Based on 41 organisms (3 kinds) in 12 frames, flooded, and soil measurements (N, pH).",
            updateNote: "Updated with the new pH reading."
        ) {}
        RecommendationCard(
            state: .ready(model), modelUnavailableReason: nil,
            basis: "Based on 41 organisms (3 kinds) in 12 frames, flooded.",
            rating: .notUseful, onRate: { _, _ in }
        ) {}
        RecommendationCard(
            state: .ready(model), modelUnavailableReason: nil,
            basis: "Based on 41 organisms (3 kinds) in 12 frames, flooded.",
            savedAt: .now.addingTimeInterval(-86_400 * 40), savedFromOlderRules: true
        ) {}
        RecommendationCard(
            state: .ready(rules), modelUnavailableReason: "Apple Intelligence is turned off in Settings."
        ) {}
        RecommendationCard(state: .generating) {}
        RecommendationCard(
            state: .generating, modelUnavailableReason: nil, progress: .choosingSteps(chosen: 2)
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
