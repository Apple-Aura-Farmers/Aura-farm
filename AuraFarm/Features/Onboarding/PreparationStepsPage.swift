import SwiftUI

/// One section of instructions: the slide, or the microscope.
///
/// The two read differently on purpose. Making the slide is a sequence somebody works
/// through with wet hands, so the arrows page back and forth and the instruction sits above
/// the drawing, where it can be reread. Setting up the microscope is a thing done once and
/// confirmed, so each step has its own Done and the drawing comes first.
struct PreparationStepsPage: View {
    var section: PreparationGuide.Section
    /// Called when the last step is finished.
    var onFinish: () -> Void

    @State private var index = 0

    private var step: PreparationGuide.Step {
        section.steps[min(index, section.steps.count - 1)]
    }

    private var isLast: Bool {
        index >= section.steps.count - 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingHeading(
                eyebrow: "Preparation", title: section.title, subtitle: section.subtitle)

            switch section.paging {
            case .arrows:
                card
                Spacer(minLength: 0)
                paged
                Spacer(minLength: 0)
            case .confirmEach:
                Spacer(minLength: 0)
                OnboardingAnimation(name: step.animation)
                Spacer(minLength: 0)
                card
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .bottom) {
            OnboardingButton(title: section.paging == .arrows ? "Continue" : "Done") {
                if isLast { onFinish() } else { advance(by: 1) }
            }
            .padding(.bottom, 8)
        }
    }

    private var card: some View {
        OnboardingStepCard(number: step.id, title: step.title, detail: step.detail)
            // Keyed on the step, so paging reads as the card being replaced rather than its
            // words changing underneath.
            .id(step.id)
            .transition(.opacity)
    }

    /// The drawing with an arrow either side.
    private var paged: some View {
        HStack(spacing: 8) {
            arrow("chevron.left", isEnabled: index > 0, by: -1)
            OnboardingAnimation(name: step.animation)
            arrow("chevron.right", isEnabled: !isLast, by: 1)
        }
    }

    private func arrow(_ symbol: String, isEnabled: Bool, by step: Int) -> some View {
        Button {
            advance(by: step)
        } label: {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(isEnabled ? Color.aura : .secondary.opacity(0.5))
                .frame(width: 32, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(step < 0 ? "Previous step" : "Next step")
    }

    private func advance(by amount: Int) {
        withAnimation(.snappy(duration: 0.2)) {
            index = min(max(index + amount, 0), section.steps.count - 1)
        }
    }
}

#Preview("Soil sample") {
    PreparationStepsPage(section: PreparationGuide.soilSample) {}
        .auraBackground()
}

#Preview("Microscope") {
    PreparationStepsPage(section: PreparationGuide.microscopeSetUp) {}
        .auraBackground()
}
