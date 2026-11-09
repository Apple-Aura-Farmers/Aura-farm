import SwiftUI

/// What one sweep came to: an estimate of the soil life seen, the counts, advice on what to
/// do, and sending it on to the Mac.
///
/// PLACEHOLDER layout: there is no final design yet. The screen only arranges the section
/// components in `Components/`, each of which takes plain values, so a new design replaces
/// this file and those views without touching how the result is worked out.
struct SoilResultScreen: View {
    private enum Content {
        case result(SoilResult)
        case failure(String)
    }

    private let content: Content
    private let recommender: any RecommendationProviding
    private let historyProvider: @Sendable (SoilResult) async -> [PastResult]
    private let adviceStore: (any AdviceStore)?

    /// The result of a saved sweep, with advice from the on-device model.
    init(sweep: SavedSweep, recommender: any RecommendationProviding = FoundationModelRecommender()) {
        do {
            content = .result(try SoilResult(sweep: sweep))
        } catch {
            content = .failure(error.localizedDescription)
        }
        self.recommender = recommender
        historyProvider = SoilResultViewModel.savedHistory
        adviceStore = FileAdviceStore()
    }

    /// A result made directly, as the test scenarios do, with its own earlier samples so
    /// nothing is read from disk.
    init(
        result: SoilResult,
        recommender: any RecommendationProviding = FoundationModelRecommender(),
        historyProvider: @escaping @Sendable (SoilResult) async -> [PastResult] = SoilResultViewModel
            .savedHistory,
        adviceStore: (any AdviceStore)? = FileAdviceStore()
    ) {
        content = .result(result)
        self.recommender = recommender
        self.historyProvider = historyProvider
        self.adviceStore = adviceStore
    }

    /// The screen for a result that could not be read.
    init(failure: String) {
        content = .failure(failure)
        recommender = RuleBasedRecommender()
        historyProvider = SoilResultViewModel.savedHistory
        adviceStore = nil
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch content {
            case .result(let result):
                SoilResultContent(
                    result: result, recommender: recommender, historyProvider: historyProvider,
                    adviceStore: adviceStore)
            case .failure(let message):
                ContentUnavailableView(
                    "No result to show",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            }
        }
        .navigationTitle("Result")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

/// The result itself, once there is one. Owns the view model so it survives redraws.
private struct SoilResultContent: View {
    @State private var viewModel: SoilResultViewModel
    /// Bumped by Try again, to restart the recommendation task.
    @State private var attempt = 0

    init(
        result: SoilResult,
        recommender: any RecommendationProviding,
        historyProvider: @escaping @Sendable (SoilResult) async -> [PastResult],
        adviceStore: (any AdviceStore)?
    ) {
        _viewModel = State(
            wrappedValue: SoilResultViewModel(
                result: result, recommender: recommender, historyProvider: historyProvider,
                adviceStore: adviceStore))
    }

    var body: some View {
        List {
            Section {
                SoilHealthCard(estimate: viewModel.estimate)
            } header: {
                Text("Soil life estimate")
            }

            Section {
                ScienceDisclaimer()
            }

            OrganismCountSection(
                total: viewModel.result.totalCount,
                rows: viewModel.breakdownRows,
                taxonomy: $viewModel.selectedTaxonomy,
                isExpanded: $viewModel.isBreakdownExpanded
            )

            Section {
                RecommendationCard(
                    state: viewModel.recommendationState,
                    modelUnavailableReason: viewModel.modelUnavailableReason,
                    progress: viewModel.progress,
                    basis: viewModel.adviceBasis,
                    savedAt: viewModel.savedAt,
                    savedFromOlderRules: viewModel.savedFromOlderRules,
                    rating: viewModel.feedback?.rating,
                    onRate: { rating, reasons in
                        Task { await viewModel.rate(rating, reasons: reasons) }
                    },
                    onRetry: { attempt += 1 }
                )
                if viewModel.canWriteAgain {
                    Button("Write again", systemImage: "arrow.clockwise") {
                        viewModel.requestFreshWording()
                        attempt += 1
                    }
                }
            } header: {
                Text("What to do next")
            }

            SampleSummarySection(result: viewModel.result)

            if let sweep = viewModel.result.sweep {
                ResultActions(sweep: sweep)
            }
        }
        .task(id: attempt) {
            await viewModel.loadRecommendation(freshWording: viewModel.wantsFreshWording)
        }
    }
}

/// Which sample this was, for the helper to check before sending it on.
private struct SampleSummarySection: View {
    let result: SoilResult

    var body: some View {
        Section("Sample") {
            LabeledContent("Sample", value: result.sampleID)
            LabeledContent("Recorded") {
                Text(result.recordedAt, format: .dateTime.day().month().hour().minute())
            }
            LabeledContent("Soil", value: result.moisture.label)
            LabeledContent("Frames kept", value: "\(result.framesKept)")
        }
    }
}
