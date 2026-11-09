#if DEBUG
    import SwiftUI

    /// What the on-device model is told about a scenario, so the team can review its input
    /// without a phone that runs Apple Intelligence. Debug builds only.
    struct AdvicePromptInspector: View {
        let scenario: ResultScenario

        @Environment(\.dismiss) private var dismiss

        var body: some View {
            List {
                textSection("Instructions", AdvicePromptBuilder.instructions())
                if let prompt {
                    textSection("Prompt", prompt)
                } else {
                    Section("Prompt") { Text("This scenario has no result, so the model is not asked.") }
                }
            }
            .navigationTitle("What the AI is told")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }

        /// Built the way the results screen builds it.
        private var prompt: String? {
            scenario.result.map { result in
                AdvicePromptBuilder.prompt(
                    for: AdviceContextBuilder().context(
                        for: result,
                        estimate: PlaceholderSoilHealthEstimator().estimate(result),
                        history: scenario.history))
            }
        }

        private func textSection(_ title: String, _ text: String) -> some View {
            Section {
                Text(text)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            } header: {
                Text(title)
            } footer: {
                Text("\(text.count) characters")
            }
        }
    }
#endif
