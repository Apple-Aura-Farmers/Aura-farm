import XCTest

@testable import AuraFarm

final class AdviceContentVersionTests: XCTestCase {
    func testTheVersionIsTheOneTheContentHasToday() {
        // If this fails, advice content changed. If that was intended, update this value; saved advice
        // written before will be marked as written with older rules.
        XCTAssertEqual(AdviceContentVersion.current, "content-81cfe9cb3e91")
    }

    func testTheFormat() {
        XCTAssertNotNil(
            AdviceContentVersion.current.range(of: #"^content-[0-9a-f]{12}$"#, options: .regularExpression),
            AdviceContentVersion.current)
    }

    func testTheValueIsStable() {
        XCTAssertEqual(AdviceContentVersion.canonicalText(), AdviceContentVersion.canonicalText())
        XCTAssertEqual(
            AdviceContentVersion.current,
            "content-"
                + String(
                    format: "%016llx", AdviceContentVersion.fnv1a64(AdviceContentVersion.canonicalText())
                )
                .prefix(12))
    }

    func testFNVMatchesTheKnownVectors() {
        XCTAssertEqual(AdviceContentVersion.fnv1a64(""), 0xcbf2_9ce4_8422_2325)
        XCTAssertEqual(AdviceContentVersion.fnv1a64("a"), 0xaf63_dc4c_8601_ec8c)
        XCTAssertEqual(AdviceContentVersion.fnv1a64("foobar"), 0x8594_4171_f739_67e8)
    }

    func testTheContentIsInTheText() {
        let text = AdviceContentVersion.canonicalText()
        for fragment in [
            AdviceReasons.stillWater, AdviceActions.all[0].wording, NeverSay.rules[0],
            "euglenoidsDominantShare",
            "minimumFramesForLow", AdvicePromptBuilder.instructions(), OrganismNotes.all[0].plainDescription,
            "highAbove", "summaryWords",
        ] {
            XCTAssertTrue(text.contains(fragment), fragment)
        }
    }

    func testEveryReasonTheBuilderProducesIsInTheList() {
        let sentences = Set(AdviceReasons.allSentences)
        XCTAssertEqual(sentences.count, AdviceReasons.allSentences.count, "no sentence is listed twice")

        for evalCase in AdviceEvalCases.all {
            let result = evalCase.result
            for level in SoilHealthEstimate.Level.allCases {
                let estimate = SoilHealthEstimate(
                    level: level, score: nil, confidence: .low, reasons: [], followUp: "")
                let context = AdviceContextBuilder().context(
                    for: result, estimate: estimate, history: evalCase.history)
                for suggested in context.actions {
                    XCTAssertTrue(
                        sentences.contains(suggested.reason), "\(evalCase.id) \(level): \(suggested.reason)")
                }
            }
        }
    }
}
