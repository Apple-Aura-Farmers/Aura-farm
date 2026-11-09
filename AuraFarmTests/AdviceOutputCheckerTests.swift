import XCTest

@testable import AuraFarm

final class AdviceOutputCheckerTests: XCTestCase {
    /// Stentor and Pyrocystis were counted but are not interpreted; Paramecium and Euglena are.
    private let context: AdviceContext = {
        let result = SoilResult(
            sampleID: "A12", recordedAt: .now, framesKept: 10, moisture: .flooded,
            countsByClass: ["paramecium": 8, "euglena": 4, "stentor": 3, "pyrocystis": 1], sweep: nil)
        let estimate = SoilHealthEstimate(
            level: .fair, score: nil, confidence: .low, reasons: [], followUp: "")
        return AdviceContextBuilder().context(for: result, estimate: estimate, history: [])
    }()

    private func problems(_ text: String, limit: Int = 100) -> [AdviceOutputChecker.Problem] {
        AdviceOutputChecker.problems(in: text, context: context, wordLimit: limit)
    }

    func testPlainTextPasses() {
        XCTAssertEqual(
            problems("Some Paramecium and Euglena were seen, at 3.4 per frame over 12 frames."), [])
    }

    func testBannedWordsMatchWholeWordsIgnoringCase() {
        XCTAssertEqual(problems("Healthy."), [.bannedWord("healthy")])
        XCTAssertEqual(problems("HEALTHY soil"), [.bannedWord("healthy")])
        XCTAssertEqual(problems("This is unhealthy."), [.bannedWord("unhealthy")])
        XCTAssertEqual(problems("A 100% result"), [.bannedWord("100%")])
        XCTAssertEqual(problems("This will cure it"), [.bannedWord("cure")])
        XCTAssertEqual(problems("A secure slide, and an obscure one"), [])
    }

    func testBannedPhrasesMatchIgnoringCase() {
        XCTAssertEqual(problems("This Will Improve things"), [.bannedWord("will improve")])
        XCTAssertEqual(problems("There is no doubt"), [.bannedWord("no doubt")])
        XCTAssertEqual(problems("Yields will increase"), [.bannedWord("will increase")])
    }

    func testDosesAreFlaggedButCountingFactsAreNot() {
        for text in [
            "Add 20 kg", "2 bags per hectare", "Use 5 litres", "once per acre", "Add 2.5 L", "10g of it",
        ] {
            XCTAssertFalse(problems(text).isEmpty, text)
        }
        for text in ["3.4 per frame", "12 frames", "30 Euglena", "2 kinds", "6 Paramecium per slide"] {
            XCTAssertEqual(problems(text), [], text)
        }
    }

    func testOrganismsThatAreNotInterpretedAreFlagged() {
        XCTAssertEqual(problems("Stentor was seen"), [.uninterpretedOrganism("Stentor")])
        XCTAssertFalse(problems("Many stentors here").isEmpty)
        XCTAssertFalse(problems("Pyrocystis is a sea organism").isEmpty)
        XCTAssertEqual(problems("Many Euglena and Paramecium were seen"), [])
    }

    func testOrganismSeenButUnknownToTheCatalogueIsFlaggedToo() {
        let result = SoilResult(
            sampleID: "A12", recordedAt: .now, framesKept: 10, moisture: .flooded,
            countsByClass: ["paramecium": 8, "Mystery": 3], sweep: nil)
        let estimate = SoilHealthEstimate(
            level: .fair, score: nil, confidence: .low, reasons: [], followUp: "")
        let context = AdviceContextBuilder().context(for: result, estimate: estimate, history: [])

        XCTAssertEqual(
            AdviceOutputChecker.problems(in: "A mystery organism", context: context, wordLimit: 50),
            [.uninterpretedOrganism("Mystery")])
    }

    func testLengthLimit() {
        let thirty = Array(repeating: "word", count: 30).joined(separator: " ")
        XCTAssertEqual(problems(thirty, limit: 30), [])
        XCTAssertEqual(problems(thirty, limit: 29), [.tooLong(words: 30, limit: 29)])
    }

    func testCheckCleansEachFieldAndNamesIt() {
        let advice = ModelAdvice(
            noticed: ["Paramecium was common.", "It is healthy."],
            picks: [
                .init(id: "resample_later", why: "Add 20 kg to be sure."),
                .init(id: "keep_notes", why: "Notes help."),
            ],
            summary: "This will improve things.")

        let (cleaned, findings) = AdviceOutputChecker.check(advice, context: context)

        XCTAssertEqual(cleaned.noticed, ["Paramecium was common."])
        XCTAssertEqual(cleaned.picks.map(\.why), ["", "Notes help."])
        XCTAssertEqual(cleaned.picks.map(\.id), ["resample_later", "keep_notes"])
        XCTAssertEqual(cleaned.summary, "")
        XCTAssertEqual(findings.map(\.field), [.noticed(1), .why("resample_later"), .summary])
    }

    func testACleanAnswerHasNoFindings() {
        let advice = ModelAdvice(
            noticed: ["Paramecium was common."], picks: [.init(id: "keep_notes", why: "Notes help.")],
            summary: "Some soil life was seen.")

        let (cleaned, findings) = AdviceOutputChecker.check(advice, context: context)

        XCTAssertEqual(cleaned, advice)
        XCTAssertEqual(findings, [])
    }

    // MARK: Word lists, Phase 5

    func testInflectedBannedWordsAreCaught() {
        for text in [
            "This guarantees better soil.", "Guaranteeing a crop", "It cured the field", "She is curing it",
        ] {
            XCTAssertFalse(problems(text).isEmpty, text)
        }
        XCTAssertEqual(problems("Do not use it; it is safe to drink."), [.bannedWord("safe to drink")])
        XCTAssertEqual(problems("It is safe to eat."), [.bannedWord("safe to eat")])
    }

    func testAmountsWithoutANumberAreCaught() {
        for text in [
            "Spread a couple of bags of compost.", "Two sacks of lime", "A handful of ash", "Handfuls of it",
            "Use a bag of it", "A sack of seed",
        ] {
            XCTAssertFalse(problems(text).isEmpty, text)
        }
        XCTAssertEqual(
            problems("Spread a couple of bags of compost."),
            [.dose("a couple of bags"), .dose("bags of")])
    }

    func testOrdinarySentencesAreNotFlagged() {
        for text in [
            "Some ciliates were seen.", "About 3.4 per frame were seen across 12 frames.",
            "Fresh water can help a still field.", "A secure slide helps.",
        ] {
            XCTAssertEqual(problems(text), [], text)
        }
    }
}
