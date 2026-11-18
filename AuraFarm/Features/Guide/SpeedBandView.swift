import SwiftUI

/// The speed band as a thin bar, with no words: green, amber or red. "Slower" is shown by the
/// instruction card, never here.
struct SpeedBandView: View {
    var band: SpeedBand

    var body: some View {
        Capsule()
            .fill(colour)
            .frame(height: 8)
            .accessibilityLabel("Speed: \(text)")
    }

    private var text: String {
        switch band {
        case .green: "good"
        case .amber: "a bit fast"
        case .red: "too fast"
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
    .padding().background(.black)
}
