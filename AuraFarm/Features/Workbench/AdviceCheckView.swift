#if DEBUG
    import SwiftUI

    /// Runs the fixed test set of samples through Apple Intelligence on the phone, grades how well
    /// the answers follow the app's rules, and exports a sheet for people to score. Debug builds
    /// only, from the workbench.
    struct AdviceCheckView: View {
        @State private var results: [AdviceEvalResult] = []
        /// 1-based position of the case being run, while running.
        @State private var running: Int?
        @State private var runTask: Task<Void, Never>?
        @State private var exportURL: URL?
        @State private var feedback: FeedbackExport?
        @State private var isLoadingFeedback = false

        private let availability = FoundationModelRecommender().availability

        /// Totals and the file for the feedback helpers gave.
        private struct FeedbackExport {
            var summary: AdviceFeedbackSummary
            var url: URL?
        }

        var body: some View {
            List {
                runSection
                if !results.isEmpty { resultsSection }
                feedbackSection
            }
            .navigationTitle("Advice check")
            .task { await loadFeedback() }
        }

        // MARK: Run

        private var runSection: some View {
            Section {
                if case .unavailable(let reason) = availability {
                    Label(reason, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
                if let running {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Running \(running) of \(AdviceEvalCases.all.count)…")
                        Spacer()
                        Button("Cancel") { runTask?.cancel() }
                    }
                } else {
                    Button("Run all \(AdviceEvalCases.all.count)", systemImage: "play.fill") { runAll() }
                        .disabled(availability != .available)
                }
                if let exportURL, running == nil {
                    ShareLink(item: exportURL) {
                        Label("Export results (CSV)", systemImage: "square.and.arrow.up")
                    }
                }
            } footer: {
                Text(
                    "This checks how well Apple Intelligence follows the app's rules. It does not check whether the advice is right for the soil; score that in the exported sheet."
                )
            }
        }

        private var resultsSection: some View {
            Section("Results") {
                ForEach(results, id: \.caseID) { result in
                    DisclosureGroup {
                        details(of: result)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title)
                            HStack(spacing: 8) {
                                badge(for: result)
                                if let seconds = result.seconds {
                                    Text(String(format: "%.1f s", seconds)).foregroundStyle(.secondary)
                                }
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }

        @ViewBuilder
        private func badge(for result: AdviceEvalResult) -> some View {
            switch result.source {
            case .rules:
                Text("standard advice").foregroundStyle(.secondary)
            case .error:
                Text("error").foregroundStyle(.red)
            case .model:
                switch result.grade?.verdict {
                case .pass?: Text("pass").foregroundStyle(.green)
                case .warn?: Text("warn").foregroundStyle(.orange)
                case .fail?: Text("fail").foregroundStyle(.red)
                case nil: EmptyView()
                }
            }
        }

        @ViewBuilder
        private func details(of result: AdviceEvalResult) -> some View {
            if let message = result.errorMessage {
                Text(message).font(.footnote)
            }
            if let recommendation = result.recommendation {
                Text(recommendation.summary).font(.footnote.weight(.semibold))
                ForEach(recommendation.noticed, id: \.self) { point in
                    Text("Noticed: \(point)").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(Array(recommendation.steps.enumerated()), id: \.offset) { index, step in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(index + 1). \(step.text)").font(.footnote)
                        if let why = step.why {
                            Text(why).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let grade = result.grade {
                ForEach(grade.notes, id: \.self) { note in
                    Label(note, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        private func runAll() {
            guard runTask == nil else { return }
            results = []
            exportURL = nil
            runTask = Task {
                // One at a time, each with its own recommender, so no session state is shared.
                for (index, evalCase) in AdviceEvalCases.all.enumerated() {
                    if Task.isCancelled { break }
                    running = index + 1
                    results.append(await run(evalCase))
                }
                running = nil
                runTask = nil
                exportURL = writeResultsFile()
            }
        }

        private func run(_ evalCase: AdviceEvalCase) async -> AdviceEvalResult {
            let estimate = PlaceholderSoilHealthEstimator().estimate(evalCase.result)
            let context = AdviceContextBuilder().context(
                for: evalCase.result, estimate: estimate, history: evalCase.history)
            func result(
                _ source: AdviceEvalResult.Source, seconds: Double? = nil, grade: AdviceAutoGrade? = nil,
                recommendation: Recommendation? = nil, error: String? = nil
            ) -> AdviceEvalResult {
                AdviceEvalResult(
                    caseID: evalCase.id, title: evalCase.title, level: estimate.level,
                    modelAsked: evalCase.modelAsked, source: source, seconds: seconds, grade: grade,
                    recommendation: recommendation, errorMessage: error)
            }

            guard evalCase.modelAsked else {
                return result(.rules, recommendation: RuleBasedRecommender.recommendation(for: context))
            }
            let clock = ContinuousClock()
            let start = clock.now
            do {
                let (advice, outcome) = try await FoundationModelRecommender().generate(
                    for: context, freshWording: false, onProgress: { _ in })
                let elapsed = clock.now - start
                let seconds =
                    Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                let grade = AdviceAutoGrade.grade(
                    advice: advice, outcome: outcome, context: context, seconds: seconds)
                return result(.model, seconds: seconds, grade: grade, recommendation: outcome.recommendation)
            } catch let failure as AdviceFailure {
                switch failure {
                case .useStandardAdvice(let note): return result(.error, error: note)
                case .retry(let message): return result(.error, error: message)
                }
            } catch {
                return result(.error, error: String(describing: error))
            }
        }

        private func writeResultsFile() -> URL? {
            let csv = AdviceEvalCSV.csv(
                results: results,
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            return Self.write(csv, named: "advice-check-\(Self.stamp()).csv")
        }

        // MARK: Feedback

        private var feedbackSection: some View {
            Section {
                if let feedback {
                    LabeledContent("Samples with feedback", value: "\(feedback.summary.sweepCount)")
                    LabeledContent("Useful", value: "\(feedback.summary.useful)")
                    LabeledContent("Not useful", value: "\(feedback.summary.notUseful)")
                    ForEach(AdviceFeedback.Reason.allCases, id: \.self) { reason in
                        if let count = feedback.summary.perReason[reason] {
                            LabeledContent(reason.label, value: "\(count)")
                        }
                    }
                    if let url = feedback.url {
                        ShareLink(item: url) {
                            Label("Export feedback (CSV)", systemImage: "square.and.arrow.up")
                        }
                    }
                } else if isLoadingFeedback {
                    ProgressView()
                }
                Button("Reload feedback", systemImage: "arrow.clockwise") {
                    Task { await loadFeedback() }
                }
            } header: {
                Text("Feedback from samples")
            }
        }

        /// Reads every saved sweep's feedback off the main actor.
        private func loadFeedback() async {
            isLoadingFeedback = true
            let loaded = await Task.detached(priority: .userInitiated) { () -> FeedbackExport in
                let store = FileAdviceFeedbackStore()
                var records: [AdviceFeedbackRecord] = []
                for sweep in SweepLibrary.sweeps() {
                    for entry in store.all(for: sweep) {
                        records.append(
                            AdviceFeedbackRecord(
                                sweepName: sweep.name,
                                sampleID: sweep.manifest?.details.sampleID ?? sweep.name,
                                recordedAt: sweep.recordedAt, feedback: entry))
                    }
                }
                let summary = AdviceFeedbackSummary(records: records)
                let url =
                    records.isEmpty
                    ? nil
                    : Self.write(
                        AdviceFeedbackCSV.csv(records: records), named: "advice-feedback-\(Self.stamp()).csv")
                return FeedbackExport(summary: summary, url: url)
            }.value
            feedback = loaded
            isLoadingFeedback = false
        }

        // MARK: Files

        private nonisolated static func stamp() -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmm"
            return formatter.string(from: Date())
        }

        private nonisolated static func write(_ text: String, named name: String) -> URL? {
            let url = URL.temporaryDirectory.appending(path: name)
            do {
                try Data(text.utf8).write(to: url, options: .atomic)
                return url
            } catch {
                return nil
            }
        }
    }

    #Preview {
        NavigationStack { AdviceCheckView() }
    }
#endif
