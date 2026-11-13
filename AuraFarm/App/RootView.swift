//
//  RootView.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 09/11/26.
//

import SwiftUI

/// Decides what the app opens on: a name, then a role, then that role's screens, and straight
/// to the screens on later launches until the person taps "Switch role".
///
/// The name stands in for signing in. Once it and a role are known this phone signs in to the
/// records anonymously under them, so a helper can mark a plot without being given an account
/// first, and what they file is still filed under somebody.
struct RootView: View {
    /// Saved between launches. Empty means nobody has said who they are yet.
    @AppStorage("operatorName") private var name = ""
    /// Saved between launches. nil means nothing has been chosen yet.
    @AppStorage("userRole") private var role: UserRole?

    @Environment(SupabaseSession.self) private var session

    var body: some View {
        Group {
            switch role {
            case _ where name.isEmpty:
                NameEntryView { name = $0 }
            case .none:
                RoleSelectionView { role = $0 }
            case .fieldHelper:
                FieldHelperHomeView(onSwitchRole: { role = nil })
            case .microscopeOperator:
                HomeView(onSwitchRole: { role = nil })
            }
        }
        .animation(.default, value: role)
        // Reports the session restored from the keychain first, so an operator who signed in
        // last week is not asked again.
        .task { await session.follow() }
        // Signs this phone in once there is a name and a role to sign in under, and never
        // again while that session lasts.
        .task(id: signInKey) {
            guard case .signedOut = session.state, let role, !name.isEmpty else { return }
            try? await session.signInAnonymously(name: name, role: role)
        }
        // Whichever comes first, picking the role or signing in, the records are told once
        // both are known, and again whenever either changes. This is what a role switch rides
        // on: the account already exists, so its profile is changed rather than made.
        .task(id: roleClaim) {
            guard let role, !roleClaim.isEmpty else { return }
            await session.claim(role, name: name)
        }
    }

    /// Changes when there is a reason to try signing in: a name, a role, or the state itself.
    private var signInKey: String {
        "\(name)-\(role?.rawValue ?? "")-\(session.state)"
    }

    /// The pairing of account and role the records have been told about. Empty until there is
    /// both an account and a role to tell them.
    private var roleClaim: String {
        guard case .signedIn(let userID, _) = session.state, let role else { return "" }
        return "\(userID.uuidString)-\(role.rawValue)"
    }
}

#Preview {
    RootView()
        .environment(FarmStore(fileURL: nil))
        .environment(SupabaseSession(client: nil))
}
