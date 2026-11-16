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
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.continue)
                        .focused($isTyping)
                        .onSubmit(submit)
                } footer: {
                    Text("Your name goes on every test and every farm you record.")
                }
            }
            .navigationTitle("Who are you?")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .bottom) {
                Button(action: submit) {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(trimmed.isEmpty)
                .padding()
            }
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
