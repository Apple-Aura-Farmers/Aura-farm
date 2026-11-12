import SwiftUI

/// Who is holding the phone, asked once before the role picker.
///
/// It stands in for signing in. Everything this phone files is filed under a name rather than
/// an account with a password, because the app is handed out inside the team and a helper in
/// a field has no business making an account before they can mark a plot.
struct NameEntryView: View {
    /// Told the name, trimmed and never empty.
    var onContinue: (String) -> Void

    @State private var name = ""
    @FocusState private var isTyping: Bool

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your name goes on every test and every farm you record.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Name", text: $name)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.continue)
                    .focused($isTyping)
                    .onSubmit(submit)
                    .font(.title3)
                    .padding(20)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))

                Spacer(minLength: 0)

                Button(action: submit) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(InvertedButtonStyle())
                .disabled(trimmed.isEmpty)
            }
            .padding(20)
            .navigationTitle("Who are you?")
            .navigationBarTitleDisplayMode(.large)
            .onAppear { isTyping = true }
        }
    }

    private func submit() {
        guard !trimmed.isEmpty else { return }
        onContinue(trimmed)
    }
}

#Preview {
    NameEntryView { _ in }
}
