#if DEBUG
    import SwiftUI

    /// Every state of the results screen, one tap each. Debug builds only, from the workbench.
    struct ResultStatesGallery: View {
        @State private var shown: ResultScenario?

        var body: some View {
            List(ResultScenario.allCases) { scenario in
                Button {
                    shown = scenario
                } label: {
                    VStack(alignment: .leading) {
                        Text(scenario.title)
                        Text(scenario.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.primary)
            }
            .navigationTitle("Result states")
            .sheet(item: $shown) { scenario in
                NavigationStack {
                    ResultScenarioScreen(scenario: scenario)
                }
            }
        }
    }

    /// The results screen as a scenario sets it up.
    struct ResultScenarioScreen: View {
        let scenario: ResultScenario

        var body: some View {
            if let result = scenario.result {
                SoilResultScreen(result: result, recommender: scenario.recommender)
            } else {
                SoilResultScreen(failure: SoilResult.Failure.noSampleDetails.localizedDescription)
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
#endif
