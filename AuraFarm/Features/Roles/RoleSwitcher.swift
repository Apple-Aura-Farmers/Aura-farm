import SwiftUI

/// The bar at the top of every screen that switches between the two roles.
struct RoleSwitcher: View {
    @Binding var role: AppRole

    var body: some View {
        Picker("Role", selection: $role) {
            ForEach(AppRole.allCases) { role in
                // A segment shows text or a picture, not both, so text it is.
                Text(role.label)
                    .tag(role)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
