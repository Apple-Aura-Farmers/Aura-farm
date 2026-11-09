import Foundation

/// Which version of the advice content wrote a saved answer.
///
/// It is worked out from the content itself: the organism notes, actions and their priority,
/// patterns, thresholds and count bands, reasons, never-say lists, output limits and the
/// model's instructions. Any change to any of them changes the version, so saved advice
/// written before the change shows the "older advice rules" caption.
///
/// The text is hashed with 64-bit FNV-1a, not `Hasher`, whose seed changes on every launch.
/// Values are written out field by field with `Mirror`, so the version does not depend on the
/// module a type lives in.
enum AdviceContentVersion {
    /// "content-" and the first 12 hex digits of the hash.
    static let current: String = {
        let hash = fnv1a64(canonicalText())
        return "content-" + String(format: "%016llx", hash).prefix(12)
    }()

    /// Everything that counts as advice content, in a fixed order.
    static func canonicalText() -> String {
        [
            "notes: " + OrganismNotes.all.map { canonical($0) }.joined(separator: "\n"),
            "actions: " + AdviceActions.all.map { canonical($0) }.joined(separator: "\n"),
            "priority: " + AdviceActions.fallbackPriority.map(\.rawValue).joined(separator: ","),
            "patterns: "
                + AdvicePattern.allCases.map {
                    [$0.rawValue, $0.title, $0.meaning, "\($0.isConcern)", "\($0.blocksImprovementActions)"]
                        .joined(separator: "|")
                }.joined(separator: "\n"),
            "thresholds: " + canonical(AdvicePatternThresholds()),
            "bands: " + canonical(CountBands()),
            "reasons: " + AdviceReasons.allSentences.joined(separator: "\n"),
            "never: " + NeverSay.rules.joined(separator: "\n"),
            "words: " + NeverSay.bannedWords.joined(separator: ","),
            "phrases: " + NeverSay.bannedPhrases.joined(separator: ","),
            "limits: " + canonical(AdviceOutputLimits()),
            "instructions: " + AdvicePromptBuilder.instructions(),
        ].joined(separator: "\n\n")
    }

    /// FNV-1a, 64 bit, over the text's UTF-8 bytes.
    static func fnv1a64(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// A value written out field by field. Sets and dictionaries are not used in the content,
    /// because their order is not fixed.
    private static func canonical(_ value: Any) -> String {
        if let text = value as? String { return "\"\(text)\"" }
        let mirror = Mirror(reflecting: value)
        switch mirror.displayStyle {
        case .optional:
            return mirror.children.first.map { canonical($0.value) } ?? "nil"
        case .struct, .class:
            return "{"
                + mirror.children.map { "\($0.label ?? "_")=\(canonical($0.value))" }.joined(separator: ",")
                + "}"
        case .collection:
            return "[" + mirror.children.map { canonical($0.value) }.joined(separator: ",") + "]"
        default:
            return "\(value)"
        }
    }
}
