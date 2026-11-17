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
    /// Why the last attempt to file this phone's role against the profile was turned away,
    /// shown on the Account screen because nothing else would say so.
    private(set) var roleProblem: String?
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

    /// Signs in without an account, under the name the person gave and the job they picked.
    ///
    /// The records see an ordinary signed-in user: Supabase gives an anonymous sign-in the
    /// `authenticated` role and its own user id, so the policies and the `created_by` default
    /// work as they do for anybody else. The name and role travel as metadata, which is where
    /// the `create_profile_for_new_user` trigger reads them to make the profile every policy
    /// then asks about.
    ///
    /// It only works where the project has anonymous sign-ins switched on, and the account is
    /// tied to this phone alone — there is no way back into it from another one.
    func signInAnonymously(name: String = "", role: UserRole? = nil) async throws {
        guard let client else { throw Failure.unavailable }
        var metadata: [String: AnyJSON] = [:]
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { metadata["full_name"] = .string(name) }
        if let role { metadata["role"] = .string(role.recordValue) }
        try await client.auth.signInAnonymously(data: metadata.isEmpty ? nil : metadata)
    }

    /// Files the name and role this phone goes by against the signed-in account's profile.
    ///
    /// The records decide what a role lets anyone do, and they take this as a claim, not an
    /// order: a project whose `profiles` policies do not let an account set its own role
    /// turns it away, and the refusal is kept here rather than thrown, because picking a role
    /// is not the moment to stop someone who may have no signal.
    func claim(_ role: UserRole, name: String = "") async {
        guard let client, case .signedIn(let userID, _) = state else { return }
        var fields: [String: AnyJSON] = ["role": .string(role.recordValue)]
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { fields["full_name"] = .string(name) }
        do {
            // Asking for the changed rows back, because a row-level security policy that
            // turns this away does not fail: it simply matches nothing, and a silent refusal
            // would be found much later, as a farm that cannot be published.
            let changed: [ProfileRow] =
                try await client
                .from("profiles")
                .update(fields)
                .eq("id", value: userID)
                .select("id")
                .execute()
                .value
            // Nothing changed means either there is no profile row to change, which is what
            // an account made before the records' trigger existed looks like, or there is one
            // and this account may not write to it. The row is the likelier of the two and
            // the one somebody can act on, so it is named first.
            roleProblem =
                changed.isEmpty
                ? "This account has no profile in the records, or may not set its own role."
                : nil
        } catch {
            roleProblem = error.localizedDescription
        }
    }

    /// Just enough of `profiles` to tell a row that changed from one that was refused.
    private struct ProfileRow: Decodable {
        var id: UUID
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
