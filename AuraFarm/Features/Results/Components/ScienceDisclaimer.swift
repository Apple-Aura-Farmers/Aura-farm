import SwiftUI

/// Says outright that nothing on the screen is backed by science, so neither the helper nor
/// the farmer takes the estimate or the advice as a lab result.
struct ScienceDisclaimer: View {
    var body: some View {
        Label {
            Text(
                "This is an early prototype. The estimate and advice are not scientifically "
                    + "tested. Use your own judgement before acting on them."
            )
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

#Preview {
    List { ScienceDisclaimer() }
}
