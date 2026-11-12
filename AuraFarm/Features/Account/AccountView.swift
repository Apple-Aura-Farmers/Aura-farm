import SwiftUI

/// Signing in, or making an account, so finished tests can be sent.
///
/// Reached from Home rather than put in front of it: a slide is often swept somewhere with
/// no signal, and a sweep that cannot be sent yet is still worth recording.
struct AccountView: View {
    @Environment(SupabaseSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var mode = Mode.signIn
    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var problem: String?
    @State private var confirmationSentTo: String?
    @State private var isWorking = false

    private enum Mode: String, CaseIterable, Identifiable {
        case signIn, signUp

        var id: String { rawValue }

        var title: String {
            switch self {
            case .signIn: return "Sign in"
            case .signUp: return "Create account"
            }
        }
    }

    /// Supabase refuses anything shorter, so it is said here rather than as a server error.
    private static let shortestPassword = 6

    private var canSubmit: Bool {
        !isWorking
            && email.contains("@")
            && password.count >= Self.shortestPassword
            && (mode == .signIn || !fullName.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                switch session.state {
                case .unavailable:
                    Section {
                        Text("This build is not set up to send tests.")
                        Text("Config/Local.xcconfig names no Supabase project.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                case .loading:
                    Section { ProgressView() }
                case .signedIn(_, let address):
                    signedIn(address)
                case .signedOut:
                    signInForm
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func signedIn(_ address: String?) -> some View {
        Section("Signed in") {
            Text(address ?? "This phone")
            Button("Sign out", role: .destructive) {
                run { try await session.signOut() }
            }
            .disabled(isWorking)
        }
        if let roleProblem = session.roleProblem {
            Section {
                Text("The records did not take this phone's role.")
                Text(roleProblem)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } footer: {
                Text("Whoever looks after the records can set it for this account instead.")
            }
        }

        Section {
            Text("Tests you finish can be sent to the farm's records.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var signInForm: some View {
        Section {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }

        Section {
            if mode == .signUp {
                TextField("Full name", text: $fullName)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
            }
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
                .textContentType(mode == .signIn ? .password : .newPassword)
        } footer: {
            if mode == .signUp {
                Text(
                    "At least \(Self.shortestPassword) characters. Someone with access to the records gives your account its role."
                )
            }
        }

        if let problem {
            Section {
                Text(problem).foregroundStyle(.red)
            }
        }

        if let confirmationSentTo {
            Section {
                Text("Open the link sent to \(confirmationSentTo), then sign in.")
            }
        }

        Section {
            Button {
                submit()
            } label: {
                HStack {
                    if isWorking { ProgressView().padding(.trailing, 4) }
                    Text(mode.title)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(!canSubmit)
        }

        Section {
            Button("Carry on without an account") {
                run { try await session.signInAnonymously() }
            }
            .disabled(isWorking)
        } footer: {
            Text(
                "The records will know this phone but not who is holding it, and the account "
                    + "cannot be reached from another phone. Only where the project allows it."
            )
        }
    }

    private func submit() {
        run {
            switch mode {
            case .signIn:
                try await session.signIn(email: email, password: password)
            case .signUp:
                switch try await session.signUp(
                    fullName: fullName, email: email, password: password)
                {
                case .signedIn:
                    break
                case .needsEmailConfirmation(let address):
                    confirmationSentTo = address
                    mode = .signIn
                }
            }
            password = ""
        }
    }

    /// Runs one account request, showing its spinner and whatever it complains about.
    private func run(_ work: @escaping () async throws -> Void) {
        problem = nil
        confirmationSentTo = nil
        isWorking = true
        Task {
            do {
                try await work()
            } catch {
                problem = error.localizedDescription
            }
            isWorking = false
        }
    }
}

#Preview {
    AccountView()
        .environment(SupabaseSession(client: nil))
}
