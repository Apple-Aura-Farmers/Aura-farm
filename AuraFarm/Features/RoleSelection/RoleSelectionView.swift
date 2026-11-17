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
            List {
                Section {
                    ForEach(UserRole.allCases) { role in
                        Button {
                            onSelect(role)
                        } label: {
                            row(for: role)
                        }
                        .foregroundStyle(.primary)
                    }
                } footer: {
                    Text("You can switch role later.")
                }
            }
            .navigationTitle("User Selection")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func row(for role: UserRole) -> some View {
        HStack(spacing: 16) {
            Image(systemName: role.systemImage)
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .frame(width: 52)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(role.title)
                    .font(.headline)
                Text(role.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        // Big targets so it can be answered with a thumb in the field.
        .padding(.vertical, 12)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the \(role.title) screens")
    }
}

#Preview {
    RoleSelectionView { _ in }
}
