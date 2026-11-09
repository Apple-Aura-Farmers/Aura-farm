#if DEBUG
    import SwiftUI

    /// Every state of the results screen, one tap each. Debug builds only, from the workbench.
    struct ResultStatesGallery: View {
        @State private var shown: ResultScenario?
        @AppStorage("resultGallery.useLiveModel") private var useLiveModel = false

        private let availability = FoundationModelRecommender().availability

        /// Off whatever the switch says when the device can't run the model.
        private var liveModelOn: Bool { useLiveModel && availability == .available }

        var body: some View {
            List {
                Section {
                    Toggle("Use Apple Intelligence", isOn: $useLiveModel)
                        .disabled(availability != .available)
                } footer: {
                    switch availability {
                    case .available:
                        Text(
                            "On: every scenario except the problem ones asks the real on-device model. "
                                + "Answers take a few seconds.")
                    case .unavailable(let reason):
                        Text("Apple Intelligence isn't available on this device: \(reason)")
                    }
                }

                Section {
                    ForEach(ResultScenario.allCases) { scenario in
                        Button {
                            shown = scenario
                        } label: {
                            VStack(alignment: .leading) {
                                Text(scenario.title)
                                HStack(spacing: 6) {
                                    Text(scenario.subtitle)
                                    if liveModelOn && !scenario.simulatesModelProblem {
                                        Label("Live", systemImage: "apple.intelligence")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .tint(.primary)
                    }
                }
            }
            .navigationTitle("Result states")
            .sheet(item: $shown) { scenario in
                NavigationStack {
                    ResultScenarioScreen(scenario: scenario, useLiveModel: liveModelOn)
                }
            }
        }
    }

    /// The results screen as a scenario sets it up.
    struct ResultScenarioScreen: View {
        let scenario: ResultScenario
        /// Ask the real on-device model, unless the scenario fakes a problem.
        var useLiveModel = false

        @State private var showsPrompt = false

        var body: some View {
            Group {
                if let result = scenario.result {
                    SoilResultScreen(
                        result: result, recommender: scenario.recommender(useLiveModel: useLiveModel),
                        historyProvider: scenario.historyProvider, adviceStore: scenario.adviceStore)
                } else {
                    SoilResultScreen(failure: SoilResult.Failure.noSampleDetails.localizedDescription)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("What the AI is told", systemImage: "text.quote") { showsPrompt = true }
                }
            }
            .sheet(isPresented: $showsPrompt) {
                NavigationStack { AdvicePromptInspector(scenario: scenario) }
            }
        }
    }

    #Preview("Gallery") {
        NavigationStack { ResultStatesGallery() }
    }

    #Preview("Lots of soil life") { NavigationStack { ResultScenarioScreen(scenario: .good) } }
    #Preview("Some soil life") { NavigationStack { ResultScenarioScreen(scenario: .fair) } }
    #Preview("Little soil life") { NavigationStack { ResultScenarioScreen(scenario: .poor) } }
    #Preview("Low count") { NavigationStack { ResultScenarioScreen(scenario: .lowCount) } }
    #Preview("Nothing counted") { NavigationStack { ResultScenarioScreen(scenario: .empty) } }
    #Preview("Detector failed") { NavigationStack { ResultScenarioScreen(scenario: .notCounted) } }
    #Preview("Mapped to groups") { NavigationStack { ResultScenarioScreen(scenario: .groupsMapped) } }
    #Preview("Missing details") { NavigationStack { ResultScenarioScreen(scenario: .missingDetails) } }
    #Preview("AI unavailable") { NavigationStack { ResultScenarioScreen(scenario: .modelUnavailable) } }
    #Preview("Advice fails") { NavigationStack { ResultScenarioScreen(scenario: .modelFails) } }
    #Preview("Advice never arrives") { NavigationStack { ResultScenarioScreen(scenario: .modelSlow) } }
    #Preview("Live model") { NavigationStack { ResultScenarioScreen(scenario: .liveModel) } }
    #Preview("Euglenoids dominant") {
        NavigationStack { ResultScenarioScreen(scenario: .euglenoidsDominant) }
    }
    #Preview("Clean-water algae") { NavigationStack { ResultScenarioScreen(scenario: .cleanWaterAlgae) } }
    #Preview("Mixed signals") { NavigationStack { ResultScenarioScreen(scenario: .mixedSignals) } }
    #Preview("Predator present") { NavigationStack { ResultScenarioScreen(scenario: .predatorPresent) } }
    #Preview("Many nematodes") { NavigationStack { ResultScenarioScreen(scenario: .nematodesHigh) } }
    #Preview("Misidentification") {
        NavigationStack { ResultScenarioScreen(scenario: .possibleMisidentification) }
    }
    #Preview("Review pile only") { NavigationStack { ResultScenarioScreen(scenario: .reviewPileOnly) } }
    #Preview("Drained, low counts") { NavigationStack { ResultScenarioScreen(scenario: .drainedLowCounts) } }
    #Preview("With history") { NavigationStack { ResultScenarioScreen(scenario: .withHistory) } }
    #Preview("AI refuses") { NavigationStack { ResultScenarioScreen(scenario: .modelBlocked) } }
    #Preview("AI busy") { NavigationStack { ResultScenarioScreen(scenario: .modelBusy) } }
    #Preview("Banned word") { NavigationStack { ResultScenarioScreen(scenario: .modelWritesBannedWord) } }
    #Preview("Several rules broken") {
        NavigationStack { ResultScenarioScreen(scenario: .modelBreaksSeveralRules) }
    }
    #Preview("Bad action ids") { NavigationStack { ResultScenarioScreen(scenario: .modelPicksBadIDs) } }
    #Preview("Saved advice") { NavigationStack { ResultScenarioScreen(scenario: .savedAdvice) } }
#endif
