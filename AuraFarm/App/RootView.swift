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
    }
}

#Preview {
    RootView()
        .environment(FarmStore(fileURL: nil))
        .environment(SupabaseSession(client: nil))
}
