//
//  RootView.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 09/11/26.
//

import SwiftUI

/// Decides what the app opens on. With no role chosen it shows the role picker; once one is
/// chosen it goes straight to that role's screens, and stays there on later launches until
/// the person taps "Switch role".
struct RootView: View {
    /// Saved between launches. nil means nothing has been chosen yet.
    @AppStorage("userRole") private var role: UserRole?

    @Environment(SupabaseSession.self) private var session

    var body: some View {
        Group {
            switch role {
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
        // Whichever comes first, picking the role or signing in, the records are told once
        // both are known, and again whenever either changes.
        .task(id: roleClaim) {
            guard let role, !roleClaim.isEmpty else { return }
            await session.claimRole(role)
        }
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
