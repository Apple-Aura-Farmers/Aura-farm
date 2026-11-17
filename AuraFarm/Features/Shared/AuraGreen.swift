import SwiftUI

extension Color {
    /// The app's one green accent (#B6DB00).
    static let aura = Color(red: 0xB6 / 255, green: 0xDB / 255, blue: 0x00 / 255)
}

extension ShapeStyle where Self == Color {
    static var aura: Color { .aura }
}
