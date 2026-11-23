import Lottie
import SwiftUI

// MARK: - Progress

/// The bar across the top of the preparation flow: one segment per section, lit up to the one
/// being shown.
struct PreparationProgress: View {
    var sections: Int
    /// Counted from 0. The segment for it and every segment before it are lit.
    var current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<max(sections, 1), id: \.self) { index in
                Capsule()
                    .fill(Color.aura.opacity(index <= current ? 1 : 0.3))
                    .frame(width: 68, height: 5)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(sections)")
    }
}

// MARK: - Animation

/// Where a step's animation goes.
///
/// Each one ships as two files, `<name>-light.json` and `<name>-dark.json`, because the
/// drawings are line art: the dark set is drawn in white and lime for a dark screen, the
/// light set in black and brown for a light one, and tinting a single file gives neither.
struct OnboardingAnimation: View {
    var name: String
    var height: CGFloat = 280

    @Environment(\.colorScheme) private var scheme

    /// What the bundled file is called, for this appearance.
    var fileName: String {
        "\(name)-\(scheme == .dark ? "dark" : "light")"
    }

    /// This appearance's file, or the other one where its twin has not been drawn yet.
    ///
    /// The fallback is a stopgap and looks it: white line art over a cream screen is close to
    /// invisible, and black line art over a brown one likewise. A step reaching for it needs
    /// its missing twin drawn, not a change here.
    private var animation: LottieAnimation? {
        let other = "\(name)-\(scheme == .dark ? "light" : "dark")"
        return LottieAnimation.named(fileName) ?? LottieAnimation.named(other)
    }

    var body: some View {
        Group {
            if let animation {
                LottieView(animation: animation)
                    .looping()
                    .resizable()
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .accessibilityHidden(true)
    }

    /// What a step whose animation has not been drawn shows: the space it will fill, and the
    /// name of the file it is waiting for.
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 20)
            .strokeBorder(
                Color.primary.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [6, 6])
            )
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "rectangle.dashed")
                        .font(.title2)
                    Text("\(fileName).json")
                        .font(.caption2.monospaced())
                }
                .foregroundStyle(.tertiary)
            }
    }
}

// MARK: - Buttons

/// The capsule at the foot of every onboarding screen.
struct OnboardingButton: View {
    var title: String
    var isEnabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(isEnabled ? Color.auraOnAccent : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(Color.aura.opacity(isEnabled ? 1 : 0.22), in: .capsule)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        // Narrower than the content it sits under, the way the design has it.
        .frame(maxWidth: 240)
        .padding(.horizontal, 24)
    }
}

// MARK: - Headings

/// The eyebrow, title and sub-line every preparation screen opens with.
struct OnboardingHeading: View {
    var eyebrow: String?
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let eyebrow {
                Text(eyebrow)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.largeTitle.bold())
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One numbered instruction, in the card that sits beside the animation.
struct OnboardingStepCard: View {
    var number: Int
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.subheadline.bold().monospacedDigit())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.auraRow, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number). \(title) \(detail)")
    }
}

#Preview("Parts") {
    VStack(spacing: 24) {
        PreparationProgress(sections: 3, current: 1)
        OnboardingHeading(
            eyebrow: "Preparation", title: "Microscope",
            subtitle: "Ensure the microscope is evenly lit.")
        OnboardingAnimation(name: "scope-1-mount", height: 220)
        OnboardingStepCard(
            number: 1, title: "Attach your phone to microscope.",
            detail: "Using the phone mount attach your phone.")
        OnboardingButton(title: "Continue") {}
    }
    .padding(24)
    .auraBackground()
}
