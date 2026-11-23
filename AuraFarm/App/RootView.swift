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
    @Environment(FarmStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch role {
            case _ where name.isEmpty:
                NameEntryView { name = $0 }
            case .none:
                RoleSelectionView { role = $0 }
            case .fieldHelper:
                FieldHelperTabs(onSwitchRole: { role = nil })
            case .microscopeOperator:
                HomeView(onSwitchRole: { role = nil })
            }
        }
        .animation(.default, value: role)
        // Reports the session restored from the keychain first, so an operator who signed in
        // last week is not asked again.
        .task { await session.follow() }
        // The records are read when the app comes to the front and every minute after, not
        // only when a screen appears. The two roles work the same farms from different
        // phones: a scientist files a result while the helper is still out in the field, and
        // the helper marks land while the scientist is at the microscope. Here rather than
        // on either role's screens, because both of them show what the other one filed.
        //
        // Keyed on the scene phase, so the loop is thrown away when the app goes to the back
        // and started again when it returns. That is what reads the records the moment the
        // app is opened: coming back to a minute-old list and waiting for the timer would
        // show the helper land somebody else has already moved.
        //
        // A pull that fails says so in the banner and the next minute tries again.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await store.pull()
                try? await Task.sleep(for: .seconds(60))
            }
        }
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
