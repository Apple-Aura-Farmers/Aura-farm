import SwiftUI

/// The colour a farmer's land is drawn in, so one glance at the map says whose is whose.
///
/// The palette carries no meaning of its own. Red, amber, green and grey are left out on
/// purpose: those are the colours the rest of the app uses to say how a test went, and a
/// farmer whose land happened to come out red would be read as a farmer in trouble.
///
/// The same farmer keeps the same colour between launches and between phones, because the
/// colour is worked out from their name rather than from where they sit in a list.
enum FarmerColour {
    /// Blues through to pinks. Distinct from each other at the size land is drawn on a map,
    /// and none of them says good or bad.
    static let palette: [Color] = [
        Color(red: 0.36, green: 0.49, blue: 0.95),  // cornflower
        Color(red: 0.58, green: 0.40, blue: 0.93),  // violet
        Color(red: 0.26, green: 0.67, blue: 0.84),  // sky
        Color(red: 0.85, green: 0.44, blue: 0.78),  // orchid
        Color(red: 0.20, green: 0.60, blue: 0.68),  // teal
        Color(red: 0.47, green: 0.36, blue: 0.80),  // indigo
        Color(red: 0.92, green: 0.49, blue: 0.62),  // rose quartz
        Color(red: 0.33, green: 0.56, blue: 0.78),  // steel
    ]

    /// The colour for each of the farmers on the phone, every one different while there are
    /// no more farmers than colours.
    ///
    /// A name picks its own colour, so adding a farmer does not repaint the others. Where two
    /// names want the same one, the later in the alphabet moves along to the next free colour,
    /// which is a rule both phones and every launch agree on. Past eight farmers the colours
    /// start again, because there are only eight that say nothing.
    static func colours(for farmerNames: [String]) -> [String: Color] {
        var byIndex: [Int: String] = [:]
        var colours: [String: Color] = [:]
        for name in Set(farmerNames.map(tidied)).sorted() {
            var index = index(for: name)
            var moved = 0
            while byIndex[index] != nil, moved < palette.count {
                index = (index + 1) % palette.count
                moved += 1
            }
            byIndex[index] = name
            colours[name] = palette[index]
        }
        return colours
    }

    /// One farmer's colour, among everyone the phone knows. Falls back to the colour the name
    /// picks for itself where the roster is not to hand.
    static func colour(for farmerName: String, among farmerNames: [String] = []) -> Color {
        colours(for: farmerNames)[tidied(farmerName)] ?? palette[index(for: farmerName)]
    }

    /// Which colour a name lands on.
    ///
    /// The hash is written out here rather than taken from `hashValue`, which Swift seeds
    /// differently on every launch: a farmer would change colour each time the app opened.
    /// Case and surrounding spaces are ignored, so "pak wayan " is the same farmer.
    static func index(for farmerName: String) -> Int {
        var hash: UInt64 = 5381
        for byte in tidied(farmerName).utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return Int(hash % UInt64(palette.count))
    }

    /// Case and surrounding spaces are ignored, so "pak wayan " is the same farmer.
    private static func tidied(_ farmerName: String) -> String {
        farmerName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
