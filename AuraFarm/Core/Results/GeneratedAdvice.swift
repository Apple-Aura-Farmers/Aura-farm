import FoundationModels

/// The shape the on-device model fills in. Properties are generated in order: noticing first
/// makes the actions follow from the evidence, and the summary comes last.
@Generable
struct GeneratedAdvice {
    @Guide(
        description:
            "1 or 2 short things noticed in this sample, using only facts from the prompt, never certain.",
        .count(1...2))
    var noticed: [String]

    @Guide(description: "2 or 3 actions picked from 'Actions you may suggest'.", .count(2...3))
    var actions: [GeneratedAction]

    @Guide(
        description: "One plain sentence to read aloud to the farmer, at most about 25 words, never certain.")
    var summary: String
}
