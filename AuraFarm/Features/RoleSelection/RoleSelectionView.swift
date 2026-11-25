//
//  RoleSelectionView.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 09/11/26.
//

import SwiftUI

/// Two large cards, one per role, shown until a role has been chosen. Tapping a card picks
/// it and Continue confirms, so a stray touch in the field does not decide for the person.
struct RoleSelectionView: View {
    /// Told which role was picked.
    var onSelect: (UserRole) -> Void

    @State private var picked: UserRole?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Select role")
                    .font(.largeTitle.bold())
                Text("You can change this later if your goals change")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)
            .padding(.bottom, 24)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ForEach(UserRole.allCases) { role in
                card(for: role)
            }
            Spacer(minLength: 0)

            Button {
                if let picked { onSelect(picked) }
            } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundStyle(Color.auraOnAccent)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(picked == nil)
        }
        .padding(.horizontal, 29)
        .padding(.bottom, 8)
        .auraBackground()
    }

    private func card(for role: UserRole) -> some View {
        let isPicked = picked == role
        let dark = scheme == .dark
        return Button {
            picked = role
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(dark ? role.illustration : role.illustration + "_Light")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 119, height: 79)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.bottom, -22) // lets the icon sit beside the title, as in the design
                    .accessibilityHidden(true)
                Text(role.title)
                    .font(.body.weight(.medium))
                Text(role.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true) // show the full summary, never truncate
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 162, alignment: .leading)
            .background(fill(isPicked), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(border(isPicked), lineWidth: 1)
            }
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }

    /// Light: the tan card turns gold when picked. Dark: it lifts towards grey.
    private func fill(_ isPicked: Bool) -> Color {
        scheme == .dark
            ? (isPicked
                ? .white.opacity(0.15) : Color(red: 40 / 255, green: 34 / 255, blue: 27 / 255).opacity(0.2))
            : (isPicked ? Color(red: 242 / 255, green: 223 / 255, blue: 174 / 255).opacity(0.8) : .auraRow)
    }

    private func border(_ isPicked: Bool) -> Color {
        scheme == .dark
            ? .white.opacity(isPicked ? 0.4 : 0.08)
            : Color.auraBrown.opacity(isPicked ? 0.53 : 0)
    }
}

#Preview {
    RoleSelectionView { _ in }
}
