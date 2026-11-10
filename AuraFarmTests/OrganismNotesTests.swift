import XCTest

@testable import AuraFarm

final class OrganismNotesTests: XCTestCase {
    private let newModelLabels = [
        "Amoeba", "Arcellinida", "Nematoda", "Monogononta", "Paramecium", "Vorticella", "Coleps",
        "Didinium", "Euglena", "Phacus", "Lepocinclis", "Dinobryon", "Micrasterias", "Stentor", "Volvox",
        "Hypotrichida", "Digononta", "Frontonia", "Closterium", "Pinnularia", "Ceratium", "Peridinium",
        "Collodictyon", "Cylindrocystis", "Pleurotaenium", "Pyrocystis",
    ]

    func testEveryNewModelLabelResolves() {
        for label in newModelLabels {
            XCTAssertNotNil(OrganismNotes.note(forLabel: label), label)
        }
    }

    func testEveryBundledLabelResolves() {
        for label in ["euglena", "paramecium", "stentor", "volvox", "vorticella"] {
            XCTAssertNotNil(OrganismNotes.note(forLabel: label), label)
        }
    }

    func testLookupIgnoresCaseAndSpaces() {
        XCTAssertEqual(OrganismNotes.note(forLabel: "Paramecium"), OrganismNotes.note(forLabel: "paramecium"))
        XCTAssertEqual(OrganismNotes.note(forLabel: " EUGLENA ")?.label, "euglena")
    }

    func testNematodaIsNematode() {
        XCTAssertEqual(OrganismNotes.note(forLabel: "Nematoda")?.label, "nematode")
    }

    func testUnknownLabelHasNoNote() {
        XCTAssertNil(OrganismNotes.note(forLabel: "rotifer"))
    }

    func testCatalogueHasEachUseInTheApprovedNumbers() {
        XCTAssertEqual(OrganismNotes.all.count, 26)
        XCTAssertEqual(OrganismNotes.all.filter { $0.use == .interpreted }.count, 13)
        XCTAssertEqual(OrganismNotes.all.filter { $0.use == .reviewPile }.count, 12)
        XCTAssertEqual(OrganismNotes.all.filter { $0.use == .trustCheck }.count, 1)
    }

    func testEveryInterpretedNoteCanBeRead() {
        for note in OrganismNotes.all where note.use == .interpreted {
            XCTAssertNotNil(note.role, note.label)
            XCTAssertNotNil(note.abundance, note.label)
            XCTAssertNotNil(note.highSuggests, note.label)
        }
        for note in OrganismNotes.all where note.use != .interpreted {
            XCTAssertNotNil(note.pileReason, note.label)
        }
    }

    func testNoNoteUsesABannedWord() {
        for note in OrganismNotes.all {
            let text = [
                note.displayName, note.plainDescription, note.highSuggests, note.lowSuggests, note.pileReason,
            ]
            .compactMap { $0 }.joined(separator: " ").lowercased()
            for word in NeverSay.bannedWords {
                XCTAssertFalse(text.contains(word), "\(note.label) says \(word)")
            }
        }
    }

    func testEveryActionIDHasARow() {
        XCTAssertEqual(AdviceActions.all.map(\.id), AdviceAction.ID.allCases)
    }
}
