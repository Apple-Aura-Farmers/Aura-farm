#if DEBUG
    import SwiftUI

    /// Four arrows under the camera picture, with their settings beside them, while the person steers the stage by hand. A press
    /// moves the stage one step; a press that stays down goes on, one step at a time.
    struct StageHandPad: View {
        let driver: AutoStageDriver
        /// Guide dry run is off: the organisms cannot be shown.
        var needsGuideDryRun = false
        var onSwitchToAutonomous: () -> Void = {}
        @AppStorage("stageLab.flipX") private var flipX = false
        @AppStorage("stageLab.flipY") private var flipY = false

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                if !driver.handNote.isEmpty {
                    Text(driver.handNote).font(.footnote).foregroundStyle(.orange)
                }
                if needsGuideDryRun {
                    Text("Turn on Guide dry run to see organisms")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    VStack(spacing: 6) {
                        arrow(.up)
                        HStack(spacing: 6) {
                            arrow(.left)
                            Color.clear.frame(width: 56, height: 56)
                            arrow(.right)
                        }
                        arrow(.down)
                    }
                    controls(driver)
                }
            }
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .onChange(of: flipX, initial: true) { _, value in driver.handFlipX = value }
            .onChange(of: flipY, initial: true) { _, value in driver.handFlipY = value }
            .onDisappear { driver.handReleaseAll() }
        }

        private func controls(_ driver: AutoStageDriver) -> some View {
            @Bindable var driver = driver
            return VStack(alignment: .leading, spacing: 6) {
                Text(driver.handSaved.map { "Manual (saved \($0.x),\($0.y))" } ?? "Manual")
                    .font(.footnote.bold())
                Text(angles).font(.caption.monospacedDigit())
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Toggle(isOn: $flipX) { Text("Flip X").frame(maxWidth: .infinity) }
                    Toggle(isOn: $flipY) { Text("Flip Y").frame(maxWidth: .infinity) }
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .lineLimit(1)
                .disabled(!driver.canChangeFlips)
                if driver.canFineStep {
                    Picker("Step", selection: $driver.handFine) {
                        Text("Normal").tag(false)
                        Text("Fine").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                Group {
                    Button {
                        driver.handStop()
                    } label: {
                        Text("Stop").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).tint(.red)
                    .controlSize(.regular)
                    if driver.handSaved != nil {
                        Button {
                            driver.goBackAndResume()
                        } label: {
                            Text("Go back and resume").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button(action: onSwitchToAutonomous) {
                            Text("Switch to autonomous").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!driver.canSwitchToAutonomous)
                    }
                }
                .controlSize(.small)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            .font(.caption)
        }

        /// A line for each servo: where it is, and its range.
        private var angles: String {
            let x = driver.limits.range(of: .x)
            let y = driver.limits.range(of: .y)
            let now = driver.stageAngles
            return "X \(now.x)° of \(x.lowerBound)–\(x.upperBound)°\n"
                + "Y \(now.y)° of \(y.lowerBound)–\(y.upperBound)°"
        }

        private func arrow(_ arrow: StageArrow) -> some View {
            HandArrowButton(
                arrow: arrow, isEnabled: driver.handEnabled(arrow),
                onPress: { driver.handPress(arrow) }, onRelease: { driver.handRelease(arrow) })
        }
    }

    /// One arrow. Press and release both matter, and a touch that is cancelled counts as a
    /// release (the gesture state resets by itself).
    private struct HandArrowButton: View {
        let arrow: StageArrow
        let isEnabled: Bool
        let onPress: () -> Void
        let onRelease: () -> Void
        @GestureState private var isDown = false
        @Environment(\.scenePhase) private var scenePhase

        var body: some View {
            Image(systemName: symbol)
                .font(.title2.bold())
                .frame(width: 56, height: 56)
                .background(isDown ? Color.accentColor : Color.accentColor.opacity(0.6), in: Circle())
                .foregroundStyle(.white)
                // Dimmed, not switched off: a press at a limit still says so, and a touch that
                // is already down is never cancelled by the others being dimmed.
                .opacity(isEnabled ? 1 : 0.35)
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($isDown) { _, state, _ in state = true }
                )
                .onChange(of: isDown) { _, down in down ? onPress() : onRelease() }
                .onChange(of: scenePhase) { _, phase in if phase != .active { onRelease() } }
                .accessibilityElement()
                .accessibilityLabel("Move \(arrow.word)")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    onPress()
                    onRelease()
                }
        }

        private var symbol: String {
            switch arrow {
            case .up: "arrow.up"
            case .down: "arrow.down"
            case .left: "arrow.left"
            case .right: "arrow.right"
            }
        }
    }
#endif
