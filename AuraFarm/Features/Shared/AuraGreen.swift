import SwiftUI

extension Color {
    /// A colour that is `light` in light mode and `dark` in dark mode.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }

    /// The green accent (#B6DB00), used in dark mode.
    static let auraGreen = Color(red: 0xB6 / 255, green: 0xDB / 255, blue: 0x00 / 255)
    /// The brown accent (#A75724), used in light mode.
    static let auraBrown = Color(red: 0xA7 / 255, green: 0x57 / 255, blue: 0x24 / 255)
    /// The app's accent: green in dark mode, brown in light mode.
    static let aura = Color(light: .auraBrown, dark: .auraGreen)
    /// Text on a filled accent button: black on the green, white on the brown.
    static let auraOnAccent = Color(light: .white, dark: .black)
}

extension ShapeStyle where Self == Color {
    static var aura: Color { .aura }
}
