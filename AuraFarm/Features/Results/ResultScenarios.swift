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
            }
        }

        var subtitle: String {
            switch self {
            case .missingDetails: return "Error screen"
            case .modelUnavailable: return "Falls back to standard advice"
            case .modelFails: return "Shows Try again"
            case .modelSlow: return "Stays on the spinner"
            case .liveModel: return "Real on-device model, fair counts"
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
            case .fair, .modelUnavailable, .modelFails, .modelSlow, .liveModel:
                return Self.result(["paramecium": 9, "euglena": 6, "vorticella": 3])
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
            }
        }

        /// What writes the advice in this scenario.
        var recommender: any RecommendationProviding {
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
            default:
                return ScenarioRecommender(behaviour: .succeed)
            }
        }

        private static func result(_ counts: [String: Int]?) -> SoilResult {
            SoilResult(
                sampleID: "DEMO-01",
                recordedAt: Date(timeIntervalSince1970: 1_793_000_000),
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
            /// Answers after a short pause, with the fixed advice marked as the model's.
            case succeed
            case fail
            case unavailable(String)
            case neverFinish
        }

        struct Failure: Error {}

        var behaviour: Behaviour
        /// Long enough to see the spinner.
        var delay: Duration = .seconds(1)

        var availability: RecommenderAvailability {
            if case .unavailable(let reason) = behaviour { return .unavailable(reason: reason) }
            return .available
        }

        func recommend(for result: SoilResult, estimate: SoilHealthEstimate) async throws -> Recommendation {
            switch behaviour {
            case .succeed, .unavailable:
                try await Task.sleep(for: delay)
                var recommendation = RuleBasedRecommender.recommendation(for: estimate.level)
                recommendation.source = .foundationModel
                return recommendation
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
