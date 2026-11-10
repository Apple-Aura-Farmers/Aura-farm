//
//  RoleSelectionView.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 09/11/26.
//

import SwiftUI

/// Two large buttons, one per role, shown until a role has been chosen. Big targets so it
/// can be answered with a thumb in the field.
struct RoleSelectionView: View {
    /// Told which role was picked.
    var onSelect: (UserRole) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ForEach(UserRole.allCases) { role in
                    Button {
                        onSelect(role)
                    } label: {
                        card(for: role)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(maxHeight: .infinity)
            .navigationTitle("User Selection")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func card(for role: UserRole) -> some View {
        HStack(spacing: 16) {
            Image(systemName: role.systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.tint)
                .frame(width: 52)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(role.title)
                    .font(.title3.bold())
                Text(role.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the \(role.title) screens")
    }
}

#Preview {
    RoleSelectionView { _ in }
}
