import XCTest

@testable import AuraFarm

final class AdviceReasonsTests: XCTestCase {
    func testTheReasonsThatChangedInPhaseFive() {
        XCTAssertEqual(
            AdviceReasons.rootPests,
            "Many tiny worms were seen. Some kinds feed on rice roots, and the app can't tell which.")
        XCTAssertEqual(
            AdviceReasons.stillWater,
            "Many Euglena-type organisms were seen, which often means still, nutrient-rich water.")
        XCTAssertEqual(
            AdviceReasons.airInSoil,
            "Still, nutrient-rich water can be short of air, and a short drain lets air in.")
        XCTAssertEqual(
            AdviceReasons.fertilizerAfterFertilizing,
            "Seen soon after fertilizing, this can mean more nutrients than the crop needs.")
        XCTAssertEqual(
            AdviceReasons.fertilizer, "A sample like this can mean more nutrients than the crop needs.")
    }

    func testEuglenoidReasonsEachStartDifferently() {
        let reasons = [
            AdviceReasons.stillWater, AdviceReasons.airInSoil, AdviceReasons.fertilizerAfterFertilizing,
            AdviceReasons.fertilizer,
        ]
        let starts = reasons.map { $0.split(separator: " ").prefix(4).joined(separator: " ") }

        XCTAssertEqual(Set(starts).count, reasons.count, "\(starts)")
    }

    func testTheNematodeReasonMakesNoJudgement() {
        let lowered = AdviceReasons.rootPests.lowercased()

        for word in ["harmless", "good", "bad", "safe"] {
            XCTAssertFalse(lowered.contains(word), word)
        }
    }

    func testNoReasonUsesABannedWordOrRunsLong() {
        for sentence in AdviceReasons.allSentences {
            let lowered = sentence.lowercased()
            for word in NeverSay.bannedWords + NeverSay.bannedPhrases {
                XCTAssertFalse(lowered.contains(word), sentence)
            }
            XCTAssertLessThanOrEqual(sentence.split(separator: " ").count, 20, sentence)
        }
    }

    func testApprovedReasonsPassTheOutputChecker() {
        let result = SoilResult(
            sampleID: "A12", recordedAt: .now, framesKept: 12, moisture: .flooded,
            countsByClass: ["paramecium": 9], sweep: nil)
        let context = AdviceContextBuilder().context(
            for: result, estimate: PlaceholderSoilHealthEstimator().estimate(result), history: [])

        for sentence in AdviceReasons.allSentences {
            XCTAssertEqual(
                AdviceOutputChecker.problems(in: sentence, context: context, wordLimit: 25), [], sentence)
        }
    }
}
