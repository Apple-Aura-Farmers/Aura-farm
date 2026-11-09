import SwiftUI

/// The app's first view: the role switcher on top, and that role's screens below it.
///
/// Switching role starts the other role's screens from the top, so nobody lands half way into
/// a form the other role opened.
struct RoleRootView: View {
    @AppStorage(AppRole.storageKey) private var role: AppRole = .fieldHelper

    var body: some View {
        Group {
            switch role {
            case .fieldHelper:
                HomeView()
            case .programManager:
                ManagerHomeView()
            }
        }
        .id(role)
        .environment(\.canEditRecords, role.canEditRecords)
        .safeAreaInset(edge: .top, spacing: 0) {
            RoleSwitcher(role: $role)
        }
    }
}

#Preview {
    RoleRootView()
        .modelContainer(for: FarmStore.models, inMemory: true)
}
