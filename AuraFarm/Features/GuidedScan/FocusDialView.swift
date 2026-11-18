import SwiftUI

/// The focus dial drawn from a reading: a horizontal track with a green zone in the middle,
/// a needle at the offset, "not far enough" on the left and "too far" on the right.
struct FocusDialView: View {
    var reading: FocusDialReading

    private var tone: Color {
        if reading.isWrongWay { return .red }
        if reading.isGreen { return .green }
        return reading.side == .past ? .orange : .white
    }

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { proxy in
                let half = proxy.size.width / 2
                ZStack {
                    Capsule().fill(.black.opacity(0.65))
                    Rectangle().fill(.green.opacity(0.55))
                        .frame(width: max(half * reading.greenHalfWidth * 2, 4))
                    Rectangle().fill(tone)
                        .frame(width: 4)
                        .offset(x: half * min(max(reading.offset, -1), 1))
                }
                .clipShape(Capsule())
            }
            .frame(height: 16)
            HStack {
                Text("not far enough")
                Spacer()
                Text("too far")
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 24)
    }
}
