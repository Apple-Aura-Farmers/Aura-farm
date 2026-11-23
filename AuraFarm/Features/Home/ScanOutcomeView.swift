import SwiftUI

/// How a scan ended: a counted result to open, or nothing to show for it.
enum ScanOutcome: Identifiable {
    case success(SavedSweep)
    case failure

    var id: String {
        switch self {
        case .success(let sweep): sweep.name
        case .failure: "failure"
        }
    }
}

/// The screen after a test: "Analysis Complete!" with See result, or "Something went wrong" with
/// Retry. Only a success leaves a result, so a failed test keeps its plot's alert on Action.
struct ScanOutcomeView: View {
    let outcome: ScanOutcome
    /// Retry was tapped. The caller reopens the scan once this screen has closed.
    var retry: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showsResult = false

    private var succeeded: Bool {
        if case .success = outcome { true } else { false }
    }

    private let cream = Color(red: 1, green: 0.99, blue: 0.97)

    var body: some View {
        NavigationStack {
            // The icon and words are centred on the screen; See result is pinned to the bottom.
            ZStack(alignment: .bottom) {
                VStack(spacing: 6) {
                    Image(succeeded ? "Success" : "Fail")
                        .resizable().scaledToFit().frame(width: 148)
                        .accessibilityHidden(true)
                        .padding(.bottom, 20)
                    Text(succeeded ? "Analysis Complete!" : "Something went wrong")
                        .font(.title3.bold())
                    Text(succeeded ? "Your soil composition profile is ready." : "Please try again.")
                        .font(.footnote)
                    if !succeeded {
                        action("Retry", systemImage: "arrow.counterclockwise") {
                            retry()
                            dismiss()
                        }
                        .padding(.top, 36)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if case .success = outcome {
                    action("See result") { showsResult = true }
                        .padding(.horizontal, 22).padding(.bottom, 8)
                }
            }
            .foregroundStyle(cream)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { backdrop }
            .overlay(alignment: .topLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.backward").font(.title3).frame(width: 36, height: 36)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .padding(.leading, 22)
                .accessibilityLabel("Back")
            }
            .navigationDestination(isPresented: $showsResult) {
                if case .success(let sweep) = outcome {
                    ScientistResultScreen(sweep: sweep, isNew: true) {
                        retry()
                        dismiss()
                    }
                }
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    /// Dark green or dark red with the tone glowing from the top.
    private var backdrop: some View {
        let base =
            succeeded
            ? Color(red: 0x11 / 255, green: 0x1B / 255, blue: 0x16 / 255)
            : Color(red: 0x1D / 255, green: 0x0E / 255, blue: 0x0B / 255)
        return
            base
            .overlay(alignment: .top) {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                (succeeded ? Color.auraGreen : Color(red: 0.85, green: 0.25, blue: 0.15))
                                    .opacity(succeeded ? 0.62 : 0.55), .clear,
                            ], center: .center, startRadius: 0, endRadius: 380)
                    )
                    .frame(width: 760, height: 760)
                    .offset(y: -150)
            }
            .ignoresSafeArea()
    }

    private func action(_ title: String, systemImage: String? = nil, perform: @escaping () -> Void)
        -> some View
    {
        Button(action: perform) {
            Group {
                if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
            }
            .font(.headline)
            .frame(maxWidth: succeeded ? .infinity : 190, minHeight: 36)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(.auraGreen)
        .foregroundStyle(.black)
    }
}

#Preview("Failed") { ScanOutcomeView(outcome: .failure) {} }
