import Foundation

/// Checks the model's own words before they are shown: banned words and phrases, amounts or
/// doses, organisms the advice must not mention, and length. Pure, so it is tested without
/// the model.
///
/// The rules mirror Table C in `docs/advice-content.md` (the team's "Advice content",
/// approved 9 November 2026). Change them in both places.
///
/// PROVISIONAL: not checked by an agronomist.
enum AdviceOutputChecker {
    enum Problem: Equatable {
        case bannedWord(String)
        /// The matched text.
        case dose(String)
        /// The display name or label.
        case uninterpretedOrganism(String)
        case tooLong(words: Int, limit: Int)
    }

    enum Field: Equatable {
        case noticed(Int)
        /// The pick's id as the model wrote it.
        case why(String)
        case summary
    }

    struct Finding: Equatable {
        var field: Field
        var problems: [Problem]
    }

    /// Phrases that give an amount without a unit next to a number.
    private static let dosePhrases = [
        "per hectare", "per acre", "/ha", "a hectare", "an acre", "a couple of bags", "bags of", "bag of",
        "sacks of", "sack of", "handful of", "handfuls of",
    ]

    private static let doseNumber = try? NSRegularExpression(
        pattern:
            #"\b\d+([.,]\d+)?\s*(kg|kilos?|g|grams?|ml|millilit(re|er)s?|l|lit(re|er)s?|bags?|sacks?|tons?|tonnes?)\b"#,
        options: [.caseInsensitive])

    static func problems(in text: String, context: AdviceContext, wordLimit: Int) -> [Problem] {
        var found: [Problem] = []

        for word in NeverSay.bannedWords where contains(text, phrase: word) {
            found.append(.bannedWord(word))
        }
        for phrase in NeverSay.bannedPhrases where text.range(of: phrase, options: .caseInsensitive) != nil {
            found.append(.bannedWord(phrase))
        }

        let whole = NSRange(text.startIndex..., in: text)
        for match in doseNumber?.matches(in: text, range: whole) ?? [] {
            if let range = Range(match.range, in: text) { found.append(.dose(String(text[range]))) }
        }
        for phrase in dosePhrases where contains(text, phrase: phrase) {
            found.append(.dose(phrase))
        }

        for name in uninterpretedNames(in: context) where contains(text, phrase: name, allowPlural: true) {
            found.append(.uninterpretedOrganism(name))
        }

        let words = text.split(whereSeparator: \.isWhitespace).count
        if words > wordLimit { found.append(.tooLong(words: words, limit: wordLimit)) }
        return found
    }

    /// Cleans the advice: a failing noticed entry is removed, and a failing reason or summary
    /// is emptied, so the mapper shows the approved wording instead. Ids are not checked here.
    static func check(
        _ advice: ModelAdvice, context: AdviceContext, limits: AdviceOutputLimits = AdviceOutputLimits()
    ) -> (cleaned: ModelAdvice, findings: [Finding]) {
        var findings: [Finding] = []
        var cleaned = advice

        cleaned.noticed = advice.noticed.enumerated().compactMap { index, text in
            let problems = problems(in: text, context: context, wordLimit: limits.noticedWords)
            guard !problems.isEmpty else { return text }
            findings.append(Finding(field: .noticed(index), problems: problems))
            return nil
        }
        cleaned.picks = advice.picks.map { pick in
            let problems = problems(in: pick.why, context: context, wordLimit: limits.whyWords)
            guard !problems.isEmpty else { return pick }
            findings.append(Finding(field: .why(pick.id), problems: problems))
            return ModelAdvice.Pick(id: pick.id, why: "")
        }
        let summaryProblems = problems(in: advice.summary, context: context, wordLimit: limits.summaryWords)
        if !summaryProblems.isEmpty {
            findings.append(Finding(field: .summary, problems: summaryProblems))
            cleaned.summary = ""
        }
        return (cleaned, findings)
    }

    // MARK: Matching

    /// Names of organisms the advice must not mention: those seen but not interpreted, and
    /// every review-pile or trust-check organism, seen or not.
    private static func uninterpretedNames(in context: AdviceContext) -> [String] {
        let known = OrganismNotes.all.filter { $0.use != .interpreted }.flatMap {
            [$0.displayName, $0.label]
        }
        let seen = context.alsoSeen.map(\.displayName)
        var names: [String] = []
        for name in seen + known
        where !name.isEmpty && !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            names.append(name)
        }
        return names
    }

    /// The phrase as a whole word or words, ignoring case. `allowPlural` also accepts a
    /// trailing "s", so "Stentors" matches "Stentor".
    private static func contains(_ text: String, phrase: String, allowPlural: Bool = false) -> Bool {
        let edge = CharacterSet.alphanumerics
        var pattern = NSRegularExpression.escapedPattern(for: phrase)
        if let first = phrase.unicodeScalars.first, edge.contains(first) {
            pattern = #"(?<![\p{L}\p{N}])"# + pattern
        }
        if allowPlural { pattern += "s?" }
        if let last = phrase.unicodeScalars.last, edge.contains(last) || allowPlural {
            pattern += #"(?![\p{L}\p{N}])"#
        }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
