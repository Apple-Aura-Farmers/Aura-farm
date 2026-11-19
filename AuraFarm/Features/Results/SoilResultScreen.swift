import SwiftUI

/// What one sweep came to: an estimate of the soil life seen, and the counts. The advice on what
/// to do next is on the farm's page on the Field Helper side.
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
    /// Whether "What to do next" is on this screen. Off in the app, where the advice is on the
    /// farm's page; the debug scenarios turn it on to look at each advice state.
    private var showsAdvice = false

    /// This screen with the advice section on.
    func showingAdvice() -> SoilResultScreen {
        var copy = self
        copy.showsAdvice = true
        return copy
    }

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
                    adviceStore: adviceStore, showsAdvice: showsAdvice)
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
    /// The map of a guided scan, read once from the sweep's folder; nil for any other sweep.
    @State private var runRecord: GuideRunRecord?
    let showsAdvice: Bool

    init(
        result: SoilResult,
        recommender: any RecommendationProviding,
        historyProvider: @escaping @Sendable (SoilResult) async -> [PastResult],
        adviceStore: (any AdviceStore)?,
        showsAdvice: Bool
    ) {
        self.showsAdvice = showsAdvice
        _runRecord = State(
            wrappedValue: result.sweep.flatMap { GuidedScanSaver.runRecord(in: $0.url) })
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

            if let runRecord {
                Section("Run map") {
                    RunMapPanel(record: runRecord)
                    // The microscope video kept with the run, to share or save to Photos.
                    if let file = runRecord.lensVideoFile, let folder = viewModel.result.sweep?.url,
                        FileManager.default.fileExists(atPath: folder.appending(path: file).path)
                    {
                        ShareLink("Share microscope video", item: folder.appending(path: file))
                    }
                }
            }

            if showsAdvice {
                WhatToDoNextSection(
                    viewModel: viewModel,
                    footer: viewModel.result.soil == nil
                        ? "Lab-only advice: from this microscope test, without the farm's soil measurements."
                        : nil)
            } else {
                Section {
                    Text(
                        "Advice for this test, combined with the farm's soil measurements, is under What to do next on the farm's page."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            SampleSummarySection(result: viewModel.result)

            if let sweep = viewModel.result.sweep {
                ResultActions(sweep: sweep)
            }
        }
    }
}

/// Which sample this was.
private struct SampleSummarySection: View {
    let result: SoilResult

    var body: some View {
        Section("Sample") {
            LabeledContent("Sample", value: result.sampleID)
            LabeledContent("Recorded") {
                Text(result.recordedAt, format: .dateTime.day().month().hour().minute())
            }
            LabeledContent("Soil", value: result.moisture.label)
            // A guided scan keeps no frames: it counts fields of view.
            if result.isGuidedScan {
                LabeledContent("Fields of view scanned", value: "\(result.viewsLooked)")
            } else {
                LabeledContent("Frames kept", value: "\(result.framesKept)")
            }
        }
    }
}
