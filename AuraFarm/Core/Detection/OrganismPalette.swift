import Foundation

/// A colour as plain numbers (0...1), so the palette stays out of SwiftUI.
struct PaletteColour: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    init(hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }
}

/// One colour per organism type for the life dots on the run map. The same label always gets the
/// same colour, in every run: the five types the model knows have fixed slots; anything else
/// shares a neutral grey.
///
/// The colours are the Okabe-Ito set, chosen to stay apart for the common kinds of colour
/// blindness, with a light blue and a pale yellow-green added to make eight.
enum OrganismPalette {
    static let colours: [PaletteColour] = [
        PaletteColour(hex: 0xE69F00), PaletteColour(hex: 0x56B4E9), PaletteColour(hex: 0x009E73),
        PaletteColour(hex: 0xF0E442), PaletteColour(hex: 0x0072B2), PaletteColour(hex: 0xD55E00),
        PaletteColour(hex: 0xCC79A7), PaletteColour(hex: 0xAEC7A0),
    ]

    /// Types beyond the palette.
    static let neutral = PaletteColour(hex: 0x9A9A9A)

    /// The labels with a slot of their own, in slot order: the detector's classes, the background
    /// slot left out.
    static let knownLabels: [String] = {
        var labels: [String] = []
        for name in DetectorModel.v3ClassNames
        where name != "no-object" && !labels.contains(name) {
            labels.append(name)
        }
        return Array(labels.prefix(colours.count))
    }()

    /// The slot of `label`, or nil for a type beyond the palette.
    static func index(for label: String) -> Int? { knownLabels.firstIndex(of: label) }

    static func colour(for label: String) -> PaletteColour {
        index(for: label).map { colours[$0] } ?? neutral
    }
}
