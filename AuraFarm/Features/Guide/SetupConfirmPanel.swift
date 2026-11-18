import SwiftUI

/// The confirmation shown over the picture when an align or focus check has passed, in the style
/// of the field review ("Does this look right?" with a button): a question, one line of what was
/// found, and Confirm. The step moves on only when it is tapped.
struct SetupConfirmPanel: View {
    var question: String
    var detail: String
    var buttonTitle: String
    var onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(question).font(.headline)
            Text(detail).font(.caption)
            Button(buttonTitle, action: onConfirm)
                .buttonStyle(.borderedProminent)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
        .padding(8)
    }
}

#Preview("Align confirmation") {
    SetupConfirmPanel(
        question: "Is the phone aligned?",
        detail: "The whole round view is in the picture, round and evenly lit.",
        buttonTitle: "Looks right", onConfirm: {}
    )
    .background(.gray)
}

#Preview("Focus confirmation") {
    SetupConfirmPanel(
        question: "Is the picture sharp?",
        detail: "Best focus found. Keep the knob still and confirm.",
        buttonTitle: "Looks right", onConfirm: {}
    )
    .background(.gray)
}
