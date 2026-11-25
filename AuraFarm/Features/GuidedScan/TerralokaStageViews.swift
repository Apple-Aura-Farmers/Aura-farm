import SwiftUI

/// How the slide moves in this test; chosen on the page's first screen and fixed once Align is
/// confirmed. Never stored beyond the last-choice defaults.
enum GuidedScanStageMode: Equatable {
    case undecided
    case terraloka(StageObjective)
    case manual
}

/// The cards the guided scan page shows for the Terraloka Stage. They share the setup card's look:
/// black background, white text, large buttons.
private struct StageCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 20))
            .foregroundStyle(.white)
    }
}

extension View {
    fileprivate func stageCard() -> some View { modifier(StageCardStyle()) }
}

/// A row that picks one option: a title, a subtitle and a radio mark.
private struct StageOptionRow: View {
    var title: String
    var subtitle: String
    var badge: String?
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title).font(.headline)
                        if let badge {
                            Text(badge).font(.caption.bold())
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Color.accentColor, in: Capsule())
                        }
                    }
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(Color.accentColor)
            }
            .padding(12)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

private func bigButton(
    _ title: String, isProminent: Bool = true, action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        Text(title).font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 56)
    }
    .buttonStyle(.borderedProminent)
    .tint(isProminent ? nil : .gray)
}

/// "How will the slide move?"
struct StageModeChoiceView: View {
    enum Option { case terraloka, manual }

    @Binding var selection: Option?
    @Binding var objective: StageObjective
    @Binding var control: StageControlMode
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How will the slide move?").font(.title3.weight(.bold))
            StageOptionRow(
                title: "Terraloka Stage", subtitle: "The stage moves the slide for you.",
                badge: nil, isSelected: selection == .terraloka
            ) { selection = .terraloka }
            StageOptionRow(
                title: "Mechanical Stage", subtitle: "You turn the knobs, guided step by step.",
                badge: nil, isSelected: selection == .manual
            ) { selection = .manual }
            if selection == .terraloka {
                Text("Objective lens").font(.headline)
                Picker("Objective lens", selection: $objective) {
                    ForEach(StageObjective.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                StageOptionRow(
                    title: "Autonomous", subtitle: "The stage scans the slide by itself.",
                    badge: "Recommended", isSelected: control == .autonomous
                ) { control = .autonomous }
                StageOptionRow(
                    title: "Manual", subtitle: "You steer with arrows. Look only, nothing is saved.",
                    badge: nil, isSelected: control == .manual
                ) { control = .manual }
            }
            if selection != nil { bigButton("Continue", action: onContinue) }
        }
        .stageCard()
    }
}

/// Setup waits here until the stage is connected.
struct StageConnectingCard: View {
    var client: StageBLEClient.Status
    var backTitle = "Back"
    var onRetry: () -> Void
    var onBack: () -> Void

    private var isWorking: Bool {
        client == .scanning || client == .connecting || client == .reconnecting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if isWorking { ProgressView().tint(.white) }
                Text(AutoStageStatus.connectionText(client))
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Retry", action: onRetry).buttonStyle(.borderedProminent)
                Button(backTitle, action: onBack).buttonStyle(.bordered).tint(.white)
            }
        }
        .stageCard()
    }
}

/// Step 4 in Terraloka mode: the stage warms up and measures itself.
struct StageCalibrationCard: View {
    var status: AutoStageStatus
    /// Stopped by Pause or by leaving the app: Resume measures again.
    var isPaused = false
    var onRetry: () -> Void
    var onResume: () -> Void = {}
    /// The person says the picture is sharp.
    var onFocused: () -> Void = {}
    /// Before the run: give up measuring and steer by hand instead; nil hides it.
    var onBackToManual: (() -> Void)?
    /// After a calibration that could not track the picture: preset moves need none.
    var onUsePreset: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(status.title).font(.title3.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            if let detail = status.detail {
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            if status.needsPerson == .focusFirst {
                Text(AutoStageAlert.focusFirst.message).font(.subheadline)
                Button("It's sharp. Calibrate", action: onFocused)
                    .buttonStyle(.borderedProminent)
            } else if status.needsPerson != nil {
                Button("Retry", action: onRetry).buttonStyle(.borderedProminent)
                if let onUsePreset {
                    Button("Use preset moves", action: onUsePreset).buttonStyle(.bordered).tint(.white)
                }
            } else if isPaused {
                Button("Resume", action: onResume).buttonStyle(.borderedProminent)
            }
            if let onBackToManual {
                Button("Back to manual", action: onBackToManual).buttonStyle(.bordered).tint(.white)
            }
        }
        .stageCard()
    }
}

/// "How should the stage cover the slide?"
struct StagePathChoiceView: View {
    @Binding var pathMode: StagePathMode
    @Binding var coverage: GuidedScanCoverage
    var objective: StageObjective

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How should the stage cover the slide?").font(.title3.weight(.bold))
            StageOptionRow(
                title: "Preset moves",
                subtitle: "Sweeps the whole stage range in even columns. No calibration needed.",
                badge: "Recommended", isSelected: pathMode == .presetPath
            ) { pathMode = .presetPath }
            StageOptionRow(
                title: "Follow the guide",
                subtitle: "Follows the live guide. Needs calibration.",
                badge: nil, isSelected: pathMode == .followGuide
            ) { pathMode = .followGuide }
            if pathMode == .followGuide {
                ForEach(GuidedScanCoverage.allCases) { option in
                    StageOptionRow(
                        title: option.title, subtitle: option.detail,
                        badge: option == GuidedScanCoverage.recommended(for: objective)
                            ? "Recommended" : nil,
                        isSelected: coverage == option
                    ) { coverage = option }
                }
            }
        }
        .stageCard()
    }
}

/// How far the preset path has come.
struct StageProgressBar: View {
    var progress: StageZigzagProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: progress.fraction)
            Text(progress.text).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sweep progress")
        .accessibilityValue(progress.text)
    }
}

/// The running scan in Terraloka mode: what the stage is doing, Pause / Resume, and a banner
/// when the person is needed.
struct StageRunStatusCard: View {
    var status: AutoStageStatus
    var isPaused: Bool
    var actions: [(title: String, run: () -> Void)]
    var onPause: () -> Void
    var onResume: () -> Void
    /// With a saved position the way on is Go back and resume, not a plain Resume.
    var hasSavedPosition = false
    var onGoBack: () -> Void = {}

    var body: some View {
        if let alert = status.needsPerson {
            // One message: the alert's own words (the status title says the same). The alert's
            // buttons and Pause or Resume sit together under it, inside the orange area.
            VStack(alignment: .leading, spacing: 8) {
                Text(alert.message).font(.headline).foregroundStyle(.black)
                if let detail = status.detail, !detail.isEmpty {
                    Text(detail).font(.subheadline).foregroundStyle(.black.opacity(0.7))
                }
                WrappingRow(spacing: 8) {
                    ForEach(actions, id: \.title) { action in
                        Button(action.title, action: action.run)
                            .buttonStyle(.borderedProminent).tint(.black)
                    }
                    pauseButtons(tint: .black)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange, in: RoundedRectangle(cornerRadius: 14))
            .stageCard()
        } else {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.title).font(.title3.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = status.detail {
                        Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isPaused {
                    VStack(alignment: .trailing, spacing: 6) { pauseButtons(tint: .white) }
                } else {
                    pauseButtons(tint: .white)
                }
            }
            .stageCard()
        }
    }

    /// Pause, or while paused Resume (Go back and resume with a saved position).
    @ViewBuilder
    private func pauseButtons(tint: Color) -> some View {
        if isPaused {
            if hasSavedPosition {
                Button("Go back and resume", action: onGoBack).buttonStyle(.borderedProminent)
            } else {
                Button("Resume", action: onResume).buttonStyle(.borderedProminent)
            }
        } else {
            Button("Pause", action: onPause).buttonStyle(.bordered).tint(tint)
        }
    }
}

/// Lays its children out left to right and wraps to the next line when they do not fit.
private struct WrappingRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let placed = arrange(subviews, width: bounds.width)
        for (subview, origin) in zip(subviews, placed.origins) {
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: widest, height: y + rowHeight), origins)
    }
}

