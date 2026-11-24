import SwiftUI

/// The first screen of a fresh install: the brand, and the way in.
///
/// It is the splash with a button on it rather than a screen of its own, so the app does not
/// appear to start twice.
struct WelcomeView: View {
    var onStart: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Image(scheme == .dark ? "Splash_Screen" : "Splash_Screen_Light")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .accessibilityHidden(true)

            Image(scheme == .dark ? "Icon" : "Icon_Light")
                .resizable()
                .scaledToFit()
                .frame(width: 132)
                .accessibilityLabel("Terra Loka")
        }
        .safeAreaInset(edge: .bottom) {
            OnboardingButton(title: "Get started", action: onStart)
                .padding(.bottom, 16)
        }
    }
}

/// What the app is for, in one line, before anybody is asked to choose a role.
struct SoilInsightsView: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            OnboardingAnimation(name: "insights-orbit", height: 300)
            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Text("Soil data to quick insights")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(
                    "We turn your field and microscope findings to quick AI-powered "
                        + "recommendations for your soil."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .safeAreaInset(edge: .bottom) {
            OnboardingButton(title: "Continue", action: onContinue)
                .padding(.bottom, 8)
        }
        .auraBackground()
    }
}

#Preview("Welcome") {
    WelcomeView {}
}

#Preview("Soil insights") {
    SoilInsightsView {}
}
