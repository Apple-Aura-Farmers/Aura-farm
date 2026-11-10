#if DEBUG
    import Foundation

    /// Made-up results for every state the results screen can be in, so each one can be
    /// looked at without a microscope or a lucky slide. Debug builds only.
    ///
    /// Add a case here for any new state; the gallery and the previews pick it up.
    enum ResultScenario: String, CaseIterable, Identifiable {
        case good
        case fair
        case poor
        case lowCount
        case empty
        case notCounted
        case groupsMapped
        case missingDetails
        case modelUnavailable
        case modelFails
        case modelSlow
        case liveModel
        case euglenoidsDominant
        case cleanWaterAlgae
        case mixedSignals
        case predatorPresent
        case nematodesHigh
        case possibleMisidentification
        case reviewPileOnly
        case drainedLowCounts
        case withHistory
        case modelBlocked
        case modelBusy
        case modelWritesBannedWord
        case modelBreaksSeveralRules
        case modelPicksBadIDs
        case savedAdvice

        var id: String { rawValue }

        var title: String {
            switch self {
            case .good: return "Lots of soil life"
            case .fair: return "Some soil life"
            case .poor: return "Little soil life"
            case .lowCount: return "Low count"
            case .empty: return "Nothing counted"
            case .notCounted: return "Detector failed"
            case .groupsMapped: return "Mostly mapped to groups"
            case .missingDetails: return "Missing sample details"
            case .modelUnavailable: return "Apple Intelligence unavailable"
            case .modelFails: return "Advice fails"
            case .modelSlow: return "Advice never arrives"
            case .liveModel: return "Live Apple Intelligence"
            case .euglenoidsDominant: return "Euglenoids dominant"
            case .cleanWaterAlgae: return "Clean-water algae"
            case .mixedSignals: return "Mixed signals"
            case .predatorPresent: return "Predator present"
            case .nematodesHigh: return "Many nematodes"
            case .possibleMisidentification: return "Possible misidentification"
            case .reviewPileOnly: return "Only uninterpreted organisms"
            case .drainedLowCounts: return "Drained field, low counts"
            case .withHistory: return "Plot with earlier samples"
            case .modelBlocked: return "Apple Intelligence refuses"
            case .modelBusy: return "Apple Intelligence is busy"
            case .modelWritesBannedWord: return "Answer uses a banned word"
            case .modelBreaksSeveralRules: return "Answer breaks several rules"
            case .modelPicksBadIDs: return "Answer picks bad actions"
            case .savedAdvice: return "Saved advice, older rules"
            }
        }

        var subtitle: String {
            switch self {
            case .missingDetails: return "Error screen"
            case .modelUnavailable: return "Falls back to standard advice"
            case .modelFails: return "Shows Try again"
            case .modelSlow: return "Stays on the spinner"
            case .liveModel: return "Real on-device model, fair counts"
            case .possibleMisidentification: return "Pyrocystis in a paddy sample"
            case .reviewPileOnly: return "Review pile only, nothing interpreted"
            case .withHistory: return "Plot North 2, two earlier results"
            case .modelBlocked: return "Standard advice, with a note"
            case .modelBusy: return "Shows Try again"
            case .modelWritesBannedWord: return "Model's steps, rules summary"
            case .modelBreaksSeveralRules: return "Rejected as a whole: standard advice"
            case .modelPicksBadIDs: return "Filled in with approved reasons"
            case .savedAdvice: return "Shows saved advice; Write again replaces it"
            default:
                guard let total = result?.totalCount else { return "No counts" }
                return "\(total) counted"
            }
        }

        /// The result to show, or nil for the scenario where there is none.
        var result: SoilResult? {
            switch self {
            case .good:
                return Self.result([
                    "paramecium": 22, "euglena": 14, "vorticella": 9, "stentor": 6, "volvox": 4,
                ])
            case .fair, .modelUnavailable, .modelFails, .modelSlow, .liveModel, .modelBlocked, .modelBusy,
                .modelWritesBannedWord, .modelBreaksSeveralRules, .modelPicksBadIDs:
                return Self.result(["paramecium": 9, "euglena": 6, "vorticella": 3])
            case .savedAdvice:
                var result = Self.result(["paramecium": 9, "euglena": 6, "vorticella": 3])
                // A sweep that is never written to: the advice comes from an in-memory store.
                result.sweep = Self.fakeSweep
                return result
            case .poor:
                return Self.result(["euglena": 7])
            case .lowCount:
                return Self.result(["paramecium": 2, "euglena": 1])
            case .empty:
                return Self.result([:])
            case .notCounted:
                return Self.result(nil)
            case .groupsMapped:
                return Self.result(["paramecium": 18, "stentor": 7, "vorticella": 11, "volvox": 2])
            case .missingDetails:
                return nil
            case .euglenoidsDominant:
                var result = Self.result(["Euglena": 30, "Phacus": 8, "Paramecium": 3])
                result.cropStage = .tillering
                result.recentActions = [.fertilized]
                return result
            case .cleanWaterAlgae:
                return Self.result([
                    "Dinobryon": 4, "Micrasterias": 3, "Vorticella": 10, "Paramecium": 8, "Amoeba": 6,
                ])
            case .mixedSignals:
                return Self.result(["Euglena": 40, "Dinobryon": 3, "Paramecium": 6])
            case .predatorPresent:
                return Self.result(["Didinium": 4, "Paramecium": 2, "Vorticella": 12, "Euglena": 5])
            case .nematodesHigh:
                return Self.result(["Nematode": 30, "Paramecium": 10, "Amoeba": 8])
            case .possibleMisidentification:
                return Self.result(["Pyrocystis": 10, "Paramecium": 12, "Euglena": 6])
            case .reviewPileOnly:
                return Self.result(["Stentor": 6, "Volvox": 5, "Closterium": 3])
            case .drainedLowCounts:
                var result = Self.result(["Paramecium": 6, "Arcellinida": 4])
                result.moisture = .drained
                result.cropStage = .ripening
                return result
            case .withHistory:
                var result = Self.result(["Paramecium": 9, "Euglena": 6, "Vorticella": 3])
                result.plotName = "North 2"
                return result
            }
        }

        /// Earlier samples of the same plot. Fixed, so no scenario reads the real sweeps.
        var history: [PastResult] {
            guard self == .withHistory else { return [] }
            let day: TimeInterval = 86_400
            return [
                PastResult(
                    recordedAt: Self.recordedAt.addingTimeInterval(-15 * day), moisture: .flooded,
                    cropStage: .tillering, organismsPerFrame: 1.1, interpretedKinds: 3, level: .fair),
                PastResult(
                    recordedAt: Self.recordedAt.addingTimeInterval(-45 * day), moisture: .flooded,
                    cropStage: .seedling, organismsPerFrame: 0.5, interpretedKinds: 1, level: .poor),
            ]
        }

        /// Hands the view model this scenario's fixed history.
        var historyProvider: @Sendable (SoilResult) async -> [PastResult] {
            let history = history
            return { _ in history }
        }

        /// True for the states that fake a model problem (or show no result at all), so they
        /// keep their stub even when the gallery asks the real model.
        var simulatesModelProblem: Bool {
            switch self {
            case .modelUnavailable, .modelFails, .modelSlow, .missingDetails, .modelBlocked, .modelBusy,
                .modelWritesBannedWord, .modelBreaksSeveralRules, .modelPicksBadIDs, .savedAdvice:
                return true
            default: return false
            }
        }

        /// What writes the advice in this scenario. With `useLiveModel`, every state that does
        /// not fake a problem asks the real on-device model.
        func recommender(useLiveModel: Bool) -> any RecommendationProviding {
            if useLiveModel && !simulatesModelProblem { return FoundationModelRecommender() }
            switch self {
            case .modelUnavailable:
                return ScenarioRecommender(
                    behaviour: .unavailable("Apple Intelligence is turned off in Settings."))
            case .modelFails:
                return ScenarioRecommender(behaviour: .fail)
            case .modelSlow:
                return ScenarioRecommender(behaviour: .neverFinish)
            case .liveModel:
                return FoundationModelRecommender()
            case .modelBlocked:
                return ScenarioRecommender(
                    behaviour: .throwFailure(.useStandardAdvice(note: AdviceFailure.refusedNote)))
            case .modelBusy:
                return ScenarioRecommender(
                    behaviour: .throwFailure(.retry(message: AdviceFailure.busyMessage)))
            case .modelWritesBannedWord:
                return ScenarioRecommender(
                    behaviour: .answer(
                        ModelAdvice(
                            noticed: ["Some soil life of three kinds was seen."],
                            picks: [
                                .init(id: "resample_later", why: "A second sample shows whether this holds."),
                                .init(id: "keep_notes", why: "Notes help the next comparison."),
                            ],
                            summary: "This soil is healthy, so keep going.")))
            case .modelBreaksSeveralRules:
                return ScenarioRecommender(
                    behaviour: .answer(
                        ModelAdvice(
                            noticed: ["Some soil life of three kinds was seen."],
                            picks: [
                                .init(id: "resample_later", why: "Add 20 kg per hectare to be sure."),
                                .init(id: "keep_notes", why: "Notes help the next comparison."),
                            ],
                            summary: "This soil is guaranteed to improve.")))
            case .modelPicksBadIDs:
                return ScenarioRecommender(
                    behaviour: .answer(
                        ModelAdvice(
                            noticed: ["Some soil life of three kinds was seen."],
                            picks: [
                                .init(id: "water_more", why: "Not an action in the catalogue."),
                                .init(id: "return_straw", why: "Real, but not offered for this sample."),
                            ],
                            summary: "Some soil life was seen, and a second sample would help.")))
            default:
                return ScenarioRecommender(behaviour: .succeed)
            }
        }

        /// Where this scenario's advice is kept: in memory, never on disk. Only `savedAdvice` has
        /// any, written with older rules so the caption says so.
        var adviceStore: any AdviceStore {
            guard self == .savedAdvice else { return InMemoryAdviceStore() }
            return InMemoryAdviceStore(saved: [Self.fakeSweep.url: Self.olderSavedAdvice])
        }

        private static let recordedAt = Date(timeIntervalSince1970: 1_793_000_000)

        private static let fakeSweep = SavedSweep(
            url: URL.temporaryDirectory.appending(
                path: "ResultScenario-savedAdvice", directoryHint: .isDirectory),
            manifest: nil, recordedAt: recordedAt, byteCount: 0, frameURLs: [], panoramaURL: nil)

        private static let olderSavedAdvice = SavedAdvice(
            recommendation: Recommendation(
                summary: "Some soil life was seen, and a second sample would help.",
                noticed: ["Example saved answer: three kinds of organism were seen."],
                steps: [
                    Recommendation.Step(
                        actionID: .resampleLater,
                        text: "Sample this field again in 2 to 4 weeks, the same way, to see if it changes.",
                        why: AdviceReasons.sampleVaries, timing: "2 to 4 weeks"),
                    Recommendation.Step(
                        actionID: .keepNotes,
                        text:
                            "Write down what you did in this field, so the next sample can be compared fairly.",
                        why: AdviceReasons.notes, timing: "Now"),
                ],
                source: .foundationModel),
            writtenAt: recordedAt.addingTimeInterval(-40 * 86_400), contentVersion: "2026-01-01-old",
            appVersion: nil)

        private static func result(_ counts: [String: Int]?) -> SoilResult {
            SoilResult(
                sampleID: "DEMO-01",
                recordedAt: recordedAt,
                framesKept: 12,
                moisture: .flooded,
                countsByClass: counts,
                sweep: nil
            )
        }
    }

    /// A stand-in for the on-device model that does exactly what a scenario asks.
    struct ScenarioRecommender: RecommendationProviding {
        enum Behaviour {
            /// Answers after a short pause, with the standard advice dressed as the model's.
            case succeed
            case fail
            case unavailable(String)
            case neverFinish
            /// Throws what the real model's recommender would, after the usual pause.
            case throwFailure(AdviceFailure)
            /// Runs a made-up model answer through the same mapper and checks as the real one.
            case answer(ModelAdvice)
        }

        struct Failure: Error {}

        var behaviour: Behaviour
        /// Long enough to see the spinner.
        var delay: Duration = .seconds(1)

        /// The steps a real answer goes through, spread over the delay so the card's text can be seen.
        private func showProgress(_ onProgress: @Sendable (AdviceProgress) -> Void) async throws {
            let pause = delay / 4
            for progress in [
                AdviceProgress.noticing, .choosingSteps(chosen: 1), .choosingSteps(chosen: 2), .summarizing,
            ] {
                onProgress(progress)
                try await Task.sleep(for: pause)
            }
        }

        var availability: RecommenderAvailability {
            if case .unavailable(let reason) = behaviour { return .unavailable(reason: reason) }
            return .available
        }

        func recommend(
            for context: AdviceContext, freshWording: Bool,
            onProgress: @escaping @Sendable (AdviceProgress) -> Void
        ) async throws -> Recommendation {
            switch behaviour {
            case .succeed, .unavailable:
                try await showProgress(onProgress)
                // Shaped like the model's answer, so its layout shows without Apple Intelligence.
                var recommendation = RuleBasedRecommender.recommendation(for: context)
                recommendation.source = .foundationModel
                recommendation.noticed = [
                    "Simulated answer: turn on Use Apple Intelligence in Result states to see the real model."
                ]
                return recommendation
            case .throwFailure(let failure):
                try await Task.sleep(for: delay)
                throw failure
            case .answer(let advice):
                try await showProgress(onProgress)
                let outcome = AdviceResponseMapper.map(advice, context: context)
                if outcome.rejectWhole {
                    throw AdviceFailure.useStandardAdvice(note: AdviceFailure.failedChecksNote)
                }
                return outcome.recommendation
            case .fail:
                try await Task.sleep(for: delay)
                throw Failure()
            case .neverFinish:
                try await Task.sleep(for: .seconds(3_600))
                throw Failure()
            }
        }
    }
#endif
