import Foundation

/// What the advice must never say, as plain rules for the model's instructions.
///
/// The content mirrors `docs/advice-content.md` (the team's "Advice content, Phase 1",
/// approved 9 November 2026). Change the content in both places.
///
/// PROVISIONAL: not checked by an agronomist.
enum NeverSay {
    static let rules: [String] = [
        "Never say \"healthy\" or \"unhealthy\" in any form.",
        "Never use words of certainty such as \"definitely\", \"proves\", \"guaranteed\" or \"will improve\".",
        "Never name a chemical, pesticide, product or brand.",
        "Never give amounts, doses or rates.",
        "Never promise yield or profit.",
        "Never talk about water being safe to drink, or about human or animal health.",
        "Never state facts that are not in the prompt, such as pH, nitrogen levels, weather or disease names.",
        "Never mention organisms that are not listed in the prompt.",
        "Never say an organism \"was not found\" unless it is listed as interpreted.",
        "Never call nematodes good or bad.",
        "Never blame the farmer.",
    ]

    /// Matched as whole words, ignoring case. PLACEHOLDER list for the team to extend.
    static let bannedWords: [String] = [
        "healthy", "unhealthy", "definitely", "guaranteed", "guarantee", "proves", "certainly", "100%",
        "cure",
        "cures", "guarantees", "guaranteeing", "cured", "curing",
    ]

    /// Matched ignoring case. PLACEHOLDER list for the team to extend.
    static let bannedPhrases: [String] = [
        "will improve", "will increase", "no doubt", "safe to drink", "safe to eat",
    ]
}
