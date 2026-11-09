import Foundation

/// A rough read of the soil from one sweep. Never shown without its confidence, the reasons
/// behind it, and when to retest, because a band on its own reads as a verdict.
struct SoilHealthEstimate: Equatable {
    enum Level: String, Equatable, CaseIterable {
        /// Plenty of organisms, of several kinds.
        case good
        case fair
        case poor
        /// Something was counted, but too little to read anything into.
        case tooFewToSay
        /// The detector did not run, so there is nothing to estimate from.
        case notCounted
    }

    enum Confidence: String, Equatable {
        case low
        case medium
        case high
    }

    var level: Level
    /// 0 to 100, or nil when there was too little to score.
    var score: Int?
    var confidence: Confidence
    /// Short, plain sentences saying what the estimate was based on.
    var reasons: [String]
    /// When to sample again or send soil to a lab. Always present, whatever the level.
    var followUp: String
}

/// Turns a result into an estimate. A protocol so the placeholder rules can be swapped for
/// a calibrated model without touching the screen.
protocol SoilHealthEstimating {
    func estimate(_ result: SoilResult) -> SoilHealthEstimate
}

/// Limits for the placeholder estimate.
///
/// PLACEHOLDERS: none of these are backed by soil science or compared with lab tests. They
/// only make the screen show something that moves with the counts. Replace them, or the
/// whole estimator, once there is real evidence.
struct SoilHealthThresholds {
    /// Fewer organisms than this in a sweep is too few to read anything into.
    var minimumCount: Int = 5
    /// Organisms per kept frame that earn the full abundance share of the score.
    var fullAbundancePerFrame: Double = 4
    /// Kinds of organism the detector knows. Finding all of them earns the full diversity share.
    var knownClasses: Int = 5
    /// Points out of 100 for how many organisms were found, and for how many kinds.
    var abundancePoints: Double = 60
    var diversityPoints: Double = 40
    /// Scores at or above these read as good, then fair; anything lower is poor.
    var goodFrom: Int = 70
    var fairFrom: Int = 40
    /// How much one organism of a class counts towards abundance. Every class counts the
    /// same for now; a class that says more about the soil can be weighted up here.
    var classWeights: [String: Double] = [:]
}

/// Scores a sweep on how much was found and how many kinds, with made-up limits.
///
/// Confidence is always low: nothing about it has been checked against a lab.
struct PlaceholderSoilHealthEstimator: SoilHealthEstimating {
    var thresholds = SoilHealthThresholds()

    func estimate(_ result: SoilResult) -> SoilHealthEstimate {
        guard let counts = result.countsByClass, let total = result.totalCount else {
            return SoilHealthEstimate(
                level: .notCounted,
                score: nil,
                confidence: .low,
                reasons: ["The detector did not run on this sweep."],
                followUp: "Run the sweep again. If it keeps failing, restart the app."
            )
        }

        guard total >= thresholds.minimumCount else {
            return SoilHealthEstimate(
                level: .tooFewToSay,
                score: nil,
                confidence: .low,
                reasons: [
                    total == 0
                        ? "Nothing was counted on the slide."
                        : "Only \(total) organisms were counted, too few to go on."
                ],
                followUp:
                    "An empty slide is usually a sampling problem. Make a fresh slide and sweep "
                    + "again before drawing any conclusion."
            )
        }

        let weighted = counts.reduce(0.0) { sum, entry in
            sum + Double(entry.value) * (thresholds.classWeights[entry.key.lowercased()] ?? 1)
        }
        let perFrame = weighted / Double(max(result.framesKept, 1))
        let abundance = min(perFrame / thresholds.fullAbundancePerFrame, 1) * thresholds.abundancePoints
        let kinds = result.classesFound
        let diversity =
            min(Double(kinds) / Double(max(thresholds.knownClasses, 1)), 1) * thresholds.diversityPoints
        let score = Int((abundance + diversity).rounded())

        let level: SoilHealthEstimate.Level =
            score >= thresholds.goodFrom ? .good : score >= thresholds.fairFrom ? .fair : .poor

        return SoilHealthEstimate(
            level: level,
            score: score,
            confidence: .low,
            reasons: [
                "About \(perFrame.formatted(.number.precision(.fractionLength(0...1)))) organisms "
                    + "per frame across \(result.framesKept) frames.",
                kinds == 1 ? "1 kind of organism found." : "\(kinds) kinds of organism found.",
                "The limits used are guesses, not checked against lab tests.",
            ],
            followUp: level == .good
                ? "Test again next season, or sooner if the crop changes."
                : "Test again in 2 to 4 weeks. If the result stays low, send a sample to a lab."
        )
    }
}
