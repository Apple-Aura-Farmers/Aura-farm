import SwiftUI

/// The guided scan page's layout, top to bottom with nothing overlapping: a top bar, the picture
/// (square; it shrinks before anything else does), and the bottom area, whose space is reserved
/// first so the instruction card is never covered or squeezed.
struct ScanLayoutView<Top: View, Picture: View, Bottom: View>: View {
    @ViewBuilder var top: Top
    @ViewBuilder var picture: Picture
    @ViewBuilder var bottom: Bottom

    var body: some View {
        VStack(spacing: 0) {
            top
            picture
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 120)
            bottom.layoutPriority(1)
        }
    }
}

#if DEBUG
    /// The page mid-run from values, with a grey disc for the camera.
    private struct MidRunPreview: View {
        var card: HelperInstruction
        var showsBoxes = false

        var body: some View {
            ScanLayoutView {
                HStack {
                    Text("32 organisms").bold()
                    Spacer()
                    Text("Column 3 of 9").bold()
                    Button("End run") {}.buttonStyle(.bordered).controlSize(.small).tint(.white)
                }
                .font(.headline.monospacedDigit())
                .padding(.horizontal)
                .padding(.vertical, 8)
            } picture: {
                ZStack(alignment: .bottomLeading) {
                    Circle().fill(.gray).aspectRatio(1, contentMode: .fit)
                    if showsBoxes {
                        RoundedRectangle(cornerRadius: 2).stroke(.green, lineWidth: 2)
                            .frame(width: 50, height: 40).offset(x: 120, y: -140)
                    }
                    // The lab's speed bar, bottom left of the picture.
                    SpeedMeter(speedFraction: 0.12).frame(width: 140).padding(8)
                }
                .padding(8)
            } bottom: {
                HelperCardView(card: card)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            .background(.black)
            .foregroundStyle(.white)
        }
    }

    private let previewTurn = HelperInstruction.turn(
        .init(knob: .bottom, way: .towardsYou, alsoOtherKnob: false))

    #Preview("Mid-run, iPhone SE size: lab speed bar, no green band") {
        MidRunPreview(card: previewTurn).frame(width: 375, height: 667)
    }
    #Preview("Mid-run, iPhone SE size: turn, large type") {
        MidRunPreview(card: previewTurn).frame(width: 375, height: 667)
            .dynamicTypeSize(.accessibility2)
    }
    #Preview("Mid-run, iPhone 17 size: Show detections on") {
        MidRunPreview(card: previewTurn, showsBoxes: true).frame(width: 402, height: 874)
    }
#endif
