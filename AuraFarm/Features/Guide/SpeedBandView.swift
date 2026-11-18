import SwiftUI

/// The speed band, small and always shown: a dot and a word.
struct SpeedBandView: View {
    var band: SpeedBand

    var body: some View {
        Label(text, systemImage: "circle.fill")
            .font(.caption.bold())
            .foregroundStyle(.white, colour)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.black.opacity(0.6), in: Capsule())
            .labelStyle(.titleAndIcon)
            .accessibilityLabel("Speed: \(text)")
    }

    private var text: String {
        switch band {
        case .green: "Speed good"
        case .amber: "A bit fast"
        case .red: "Too fast"
        }
    }

    private var colour: Color {
        switch band {
        case .green: .green
        case .amber: .orange
        case .red: .red
        }
    }
}

#Preview {
    VStack {
        SpeedBandView(band: .green)
        SpeedBandView(band: .amber)
        SpeedBandView(band: .red)
    }
    .padding().background(.gray)
}
