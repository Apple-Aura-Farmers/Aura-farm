import SwiftUI

/// "What you'll need": the kit to gather, ticked off one at a time.
///
/// Continue stays off until every line is ticked. Somebody halfway through a slide with no
/// cover slips has wasted the sample, so the list is a gate and not a reminder.
struct PreparationChecklistPage: View {
    var materials: [PreparationGuide.Material]
    var onContinue: () -> Void

    /// What has been ticked, by material id.
    @State private var ticked: Set<String> = []

    private var isComplete: Bool {
        ticked.count == materials.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                OnboardingHeading(
                    eyebrow: "Preparation", title: "What you'll need",
                    subtitle: "Ensure you have the materials needed to continue")

                VStack(spacing: 0) {
                    ForEach(Array(materials.enumerated()), id: \.element.id) { index, material in
                        row(material, isLast: index == materials.count - 1)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            // Clears the button, which floats over the list rather than ending it.
            .padding(.bottom, 96)
        }
        .safeAreaInset(edge: .bottom) {
            OnboardingButton(title: "Continue", isEnabled: isComplete, action: onContinue)
                .padding(.bottom, 8)
        }
        .scrollContentBackground(.hidden)
    }

    /// A ticked line lifts onto a card of its own; an unticked one stays flat in the list.
    private func row(_ material: PreparationGuide.Material, isLast: Bool) -> some View {
        let isTicked = ticked.contains(material.id)
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                if isTicked { ticked.remove(material.id) } else { ticked.insert(material.id) }
            }
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    tick(isTicked)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(material.title)
                            .font(.body.weight(.medium))
                        Text(material.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 14)

                if !isTicked && !isLast {
                    Divider().opacity(0.4).padding(.leading, 52)
                }
            }
            .background(isTicked ? Color.auraRow : .clear, in: .rect(cornerRadius: 14))
            .padding(.vertical, isTicked ? 4 : 0)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(material.title). \(material.detail)")
        .accessibilityAddTraits(isTicked ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isTicked ? "Tap to untick" : "Tap to tick off")
    }

    private func tick(_ isTicked: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isTicked ? Color.aura : .clear)
            Circle()
                .strokeBorder(isTicked ? .clear : Color.primary.opacity(0.3), lineWidth: 1.5)
            if isTicked {
                Image(systemName: "checkmark")
                    .font(.footnote.bold())
                    .foregroundStyle(Color.auraOnAccent)
            }
        }
        .frame(width: 26, height: 26)
    }
}

#Preview("Makes the slide") {
    PreparationChecklistPage(materials: PreparationGuide.materials(preparingSample: true)) {}
        .auraBackground()
}

#Preview("Handed the sample") {
    PreparationChecklistPage(materials: PreparationGuide.materials(preparingSample: false)) {}
        .auraBackground()
}
