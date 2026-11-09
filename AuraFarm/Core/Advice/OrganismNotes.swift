import Foundation

/// Every organism the detectors know: the bundled 5-class model and the team's 26-class one.
///
/// The content mirrors `docs/advice-content.md` (the team's "Advice content, Phase 1",
/// approved 9 November 2026). Change the content in both places.
///
/// PROVISIONAL: not checked by an agronomist. Rows marked `.must` need expert review.
enum OrganismNotes {
    /// The note for a model label, in any case. nil for a label no note covers, which the
    /// advice treats like the review pile: seen, but not interpreted.
    static func note(forLabel label: String) -> OrganismNote? {
        let key = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return byLabel[aliases[key] ?? key]
    }

    /// Other names a model uses for the same class.
    private static let aliases = ["nematoda": "nematode"]

    private static let byLabel = Dictionary(uniqueKeysWithValues: all.map { ($0.label, $0) })

    static let all: [OrganismNote] = interpreted + reviewPile + trustCheck

    private static let interpreted: [OrganismNote] = [
        read(
            "amoeba", "Naked amoebae", .bacteriaFeeder, .common,
            "A shapeless, slow-crawling single cell",
            high: "Lots of bacterial grazing; in soil, amoebae are a main driver of releasing nitrogen "
                + "to plants",
            low: "Hard to spot, so a low count is often just missed ones", review: .should),
        read(
            "arcellinida", "Testate amoebae", .bacteriaFeeder, .moderate,
            "An amoeba living inside a small shell",
            high: "Moist soil rich in organic matter; they were about five times more common under "
                + "organic farming in one trial",
            low: "Drier soil, or less organic matter", review: .should),
        read(
            "nematode", "Nematodes", .mixed, .common, "A tiny worm",
            high: "An active food web, but some nematodes are rice root pests; the app cannot tell "
                + "which kind, so a high count is neither good nor bad on its own",
            low: notAConcern, review: .must),
        read(
            "monogononta", "Monogonont rotifers", .bacteriaFeeder, .moderate,
            "A tiny animal with a crown of beating hairs",
            high: "Nutrient enrichment; rotifers respond strongly to added nitrogen and phosphorus in "
                + "fresh water",
            low: notAConcern, review: .should),
        read(
            "paramecium", "Paramecium", .bacteriaFeeder, .common,
            "A fast, slipper-shaped single cell covered in tiny hairs",
            high: "Plenty of bacteria from rotting matter; it tolerates dirty, low-oxygen water, so "
                + "lots of them is not a good sign on its own",
            low: "Little organic matter, or the sample dried out", review: .should),
        read(
            "vorticella", "Vorticella", .bacteriaFeeder, .common, "A bell-shaped cell on a spring-like stalk",
            high: "Enough oxygen and good bacterial activity", low: "Low oxygen", review: .should),
        read(
            "coleps", "Coleps", .mixed, .moderate, "A small barrel-shaped cell with a plated shell",
            high: "Moderately enriched water; it is rated as tolerating moderate pollution",
            low: notAConcern, review: .should),
        read(
            "didinium", "Didinium", .predator, .scarce, "A barrel-shaped cell that hunts Paramecium",
            high: "There is a predator level in the food web, which means enough prey to support it",
            low: "Normal; it is naturally scarcer than its prey", review: .should),
        read(
            "euglena", "Euglena", .lightAndDissolved, .common, "A small green swimmer with a whip-like tail",
            high: "Nutrient-rich, still water; possibly too much nitrogen", low: normal, review: .must),
        read(
            "phacus", "Phacus", .lightAndDissolved, .moderate, "A flat, leaf-shaped relative of Euglena",
            high: "Same as Euglena: high nutrients", low: normal, review: .should),
        read(
            "lepocinclis", "Lepocinclis", .lightAndDissolved, .moderate,
            "A spindle-shaped relative of Euglena",
            high: "Same as Euglena; the evidence is for the group, not this genus", low: normal,
            review: .should),
        read(
            "dinobryon", "Dinobryon", .alga, .scarce, "A branching golden alga living in little cups",
            high: "Low nutrients, especially low phosphorus; it does well in clean, nutrient-poor water",
            low: normal, review: .must),
        read(
            "micrasterias", "Micrasterias", .alga, .scarce, "A flat, star-shaped green alga",
            high: "Clean, low-nutrient, slightly acidic water", low: normal, review: .must),
    ]

    private static let reviewPile: [OrganismNote] = [
        pile("stentor", "Stentor", "The evidence conflicts; nothing found for paddies."),
        pile("volvox", "Volvox", "Comes and goes quickly; no paddy evidence found."),
        pile(
            "hypotrichida", "Hypotrich ciliates",
            "Often the main ciliates in soil, but no evidence of what they indicate."),
        pile(
            "digononta", "Bdelloid rotifers",
            "Very widespread and survive drying, so they do not signal much."),
        pile("frontonia", "Frontonia", "Only one river study."),
        pile("closterium", "Closterium", "Meaning depends on the species."),
        pile("pinnularia", "Pinnularia", "Favours acidic soil but is broadly tolerant."),
        pile("ceratium", "Ceratium", "Lake plankton; nothing found for paddies."),
        pile("peridinium", "Peridinium", "Nothing usable found."),
        pile("collodictyon", "Collodictyon", "Rare; no indicator meaning found."),
        pile("cylindrocystis", "Cylindrocystis", "Nothing found."),
        pile("pleurotaenium", "Pleurotaenium", "Nothing found."),
    ]

    private static let trustCheck: [OrganismNote] = [
        OrganismNote(
            label: "pyrocystis", displayName: "Pyrocystis", use: .trustCheck, role: nil, abundance: nil,
            plainDescription: "A sea organism", highSuggests: nil, lowSuggests: nil, confidence: .low,
            review: .light,
            pileReason: "A sea organism, so in a paddy sample it is probably a misidentification.")
    ]

    /// Low-count texts the prompt leaves out, because they say nothing.
    static let normal = "Normal"
    static let notAConcern = "Not a concern on its own"

    private static func read(
        _ label: String, _ name: String, _ role: OrganismNote.Role, _ abundance: OrganismNote.Abundance,
        _ description: String, high: String, low: String, review: OrganismNote.ReviewNeed
    ) -> OrganismNote {
        OrganismNote(
            label: label, displayName: name, use: .interpreted, role: role, abundance: abundance,
            plainDescription: description, highSuggests: high, lowSuggests: low, confidence: .medium,
            review: review, pileReason: nil)
    }

    private static func pile(_ label: String, _ name: String, _ reason: String) -> OrganismNote {
        OrganismNote(
            label: label, displayName: name, use: .reviewPile, role: nil, abundance: nil,
            plainDescription: name, highSuggests: nil, lowSuggests: nil, confidence: .low, review: .must,
            pileReason: reason)
    }
}
