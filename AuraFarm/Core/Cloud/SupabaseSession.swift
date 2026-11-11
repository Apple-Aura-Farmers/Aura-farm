import Foundation
import Supabase

/// Who is signed in on this phone.
///
/// Sweeps are saved to the phone whether or not anyone is signed in, because the microscope
/// is often somewhere with no signal. Signing in is what lets a saved sweep be sent, so this
/// gates sending and never gates recording.
@MainActor @Observable
final class SupabaseSession {
    enum State: Equatable {
        /// Config/Local.xcconfig names no project, so there is nothing to sign in to.
        case unavailable
        /// Still reading the session kept from the last launch.
        case loading
        case signedOut
        case signedIn(userID: UUID, email: String?)
    }

    /// What signing up led to, which is not always a signed-in account.
    enum SignUpOutcome: Equatable {
        case signedIn
        /// The project has email confirmation switched on, so the account exists but cannot
        /// be used until the link in the email is opened.
        case needsEmailConfirmation(email: String)
    }

    private(set) var state: State
    private let client: SupabaseClient?

    init(client: SupabaseClient? = Cloud.client) {
        self.client = client
        self.state = client == nil ? .unavailable : .loading
    }

    /// Follows the sign-in state for as long as the caller's view is on screen.
    ///
    /// The first thing this reports is the session restored from the keychain, which is why
    /// the starting state is `loading` rather than `signedOut`: showing a sign-in screen for
    /// the moment that read takes would make an already signed-in operator sign in again.
    func follow() async {
        guard let client else { return }
        for await (_, session) in client.auth.authStateChanges {
            state = Self.state(for: session)
        }
    }

    /// Makes an account and signs in with it.
    ///
    /// `fullName` goes in the account's metadata, where the `create_profile_for_new_user`
    /// trigger copies it into `profiles.full_name`. The role is not sent: the app cannot be
    /// trusted to pick it, so a new account has none until someone grants it one.
    func signUp(fullName: String, email: String, password: String) async throws -> SignUpOutcome {
        guard let client else { throw Failure.unavailable }
        let name = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let response = try await client.auth.signUp(
            email: address,
            password: password,
            data: name.isEmpty ? nil : ["full_name": .string(name)]
        )
        guard response.session != nil else {
            return .needsEmailConfirmation(email: address)
        }
        return .signedIn
    }

    func signIn(email: String, password: String) async throws {
        guard let client else { throw Failure.unavailable }
        try await client.auth.signIn(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
    }

    func signOut() async throws {
        guard let client else { throw Failure.unavailable }
        try await client.auth.signOut()
    }

    enum Failure: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "This build is not set up to send tests."
        }
    }

    /// nil session means signed out. Kept separate so it can be checked without a project.
    static func state(for session: Session?) -> State {
        guard let session else { return .signedOut }
        return .signedIn(userID: session.user.id, email: session.user.email)
    }
}
