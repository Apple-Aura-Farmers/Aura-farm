import SwiftUI

// The Scan page's views, drawn from `ScanPageState` and `ScanPageActions` alone. None of them
// reads the driver or the engine.

/// The ladybug: the eye's job. White, 36 pt.
struct ScanLadybugButton: View {
    var showsBoxes: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: showsBoxes ? "ladybug.circle" : "ladybug.slash.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.white)
        }
        .accessibilityLabel("Show detections")
        .accessibilityValue(showsBoxes ? "On" : "Off")
    }
}

/// The X, the farm and plot with the date, End, and under it Pause or Resume.
struct ScanTopBar: View {
    var top: ScanTopState
    var actions: ScanPageActions
    /// The mechanical stage keeps its ladybug up here; nil leaves it out.
    var ladybug: (showsBoxes: Bool, action: () -> Void)?

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 2) {
                Text(top.title).bold().lineLimit(1).minimumScaleFactor(0.6)
                Text(top.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline).foregroundStyle(.secondary)
                    #if DEBUG
                        .onLongPressGesture { actions.longPressDate?() }
                    #endif
            }
            .padding(.horizontal, 100)
            .frame(height: 44)
            HStack(alignment: .top) {
                VStack(spacing: 4) {
                    Button(action: actions.close) {
                        Image(systemName: "xmark").font(.headline)
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.12), in: Circle())
                    }
                    .accessibilityLabel("Close")
                    if let ladybug {
                        ScanLadybugButton(showsBoxes: ladybug.showsBoxes, action: ladybug.action)
                            .font(.title2)
                    }
                }
                Spacer()
                // Pause is centred under End.
                VStack(spacing: 4) {
                    endMenu
                    if let pause = top.pause {
                        Button(action: actions.togglePause) {
                            Label(pause.title, systemImage: pause.symbol)
                        }
                        .font(.body)
                        .foregroundStyle(Color.auraGreen)
                        .frame(height: 28)
                    } else {
                        Color.clear.frame(height: 28)
                    }
                }
            }
        }
        .font(.headline)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var endMenu: some View {
        Menu {
            ForEach(top.endItems, id: \.title) { item in
                Button(item.title, role: item == .discard ? .destructive : nil) {
                    actions.chooseEnd(item)
                }
            }
        } label: {
            Label(top.endLabel, systemImage: "flag.checkered")
                .font(.body)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.auraGreen, in: Capsule())
                .foregroundStyle(.black)
        }
        .disabled(!top.endEnabled)
    }
}

/// Under the lens: the status, the Auto | Manual switch and the card.
struct ScanBottomView: View {
    var state: ScanPageState
    var actions: ScanPageActions

    var body: some View {
        VStack(spacing: 12) {
            status
            ScanModeSwitch(
                mode: state.mode, isEnabled: state.switchEnabled, onChange: actions.setMode)
            ScanCardView(state: state, actions: actions)
                .padding(.top, 16)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    /// Two centred lines; in Auto the ladybug sits to the right and the text stays centred on
    /// the screen.
    private var status: some View {
        let status = state.status
        return ZStack {
            VStack(spacing: 2) {
                Text(status.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(status.isWarning ? Color.orange : .white)
                if let detail = status.detail {
                    Text(detail).font(.system(size: 14)).foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 56)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { if status.isReminder { actions.dismissReminder() } }
            if state.mode == .auto {
                HStack {
                    Spacer()
                    ScanLadybugButton(showsBoxes: state.showsBoxes, action: actions.toggleBoxes)
                }
            }
        }
        .frame(minHeight: 52)
        .padding(.top, 4)
    }
}

/// Auto | Manual: the selected half green with dark text, the other grey with green text.
struct ScanModeSwitch: View {
    var mode: ScanMode
    var isEnabled: Bool
    var onChange: (ScanMode) -> Void

    var body: some View {
        HStack(spacing: 0) {
            segment("Auto", .auto)
            segment("Manual", .manual)
        }
        .frame(maxWidth: 355).frame(height: 28)
        .background(.white.opacity(0.12), in: Capsule())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Stage control")
    }

    private func segment(_ title: String, _ value: ScanMode) -> some View {
        let isSelected = mode == value
        return Button {
            if !isSelected { onChange(value) }
        } label: {
            Text(title).font(.callout)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(isSelected ? Color.auraGreen : .clear, in: Capsule())
                .foregroundStyle(isSelected ? Color.black : Color.auraGreen)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The one place under the switch: a dark rounded card with a thin border.
struct ScanCardView: View {
    var state: ScanPageState
    var actions: ScanPageActions

    private static let rowHeight: CGFloat = 43

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.1), lineWidth: 1))
    }

    @ViewBuilder
    private var content: some View {
        switch state.card {
        case .found(let rows): found(rows)
        case .focus(let dial, let canConfirmEmptyArea): focus(dial, canConfirmEmptyArea)
        case .alert(let buttons): alert(buttons)
        case .manualPad: ScanManualPad(state: state, actions: actions)
        }
    }

    @ViewBuilder
    private func found(_ rows: [ScanFoundRow]) -> some View {
        if rows.isEmpty {
            Text("No Organisms Detected")
                .font(.system(size: 18)).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 95)
                .padding(.horizontal)
        } else {
            // About three rows show; only this list scrolls, never the page.
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        HStack {
                            Text(row.name).font(.system(size: 18, weight: .medium))
                            Spacer()
                            Text("\(row.count) Found").font(.system(size: 18)).foregroundStyle(.secondary)
                        }
                        .frame(height: Self.rowHeight)
                        if row != rows.last { Divider().overlay(.white.opacity(0.1)) }
                    }
                }
                .padding(.horizontal, 14)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: Self.rowHeight * CGFloat(min(rows.count, 3)) + 8)
            .accessibilityLabel("Organisms found so far")
        }
    }

    private func focus(_ dial: FocusDialReading?, _ canConfirmEmptyArea: Bool) -> some View {
        VStack(spacing: 10) {
            if let dial { FocusDialView(reading: dial) }
            cardButton("Resume anyway", isProminent: true)
            if canConfirmEmptyArea { cardButton("In focus – empty area", isProminent: false) }
        }
        .padding(.vertical, 14)
    }

    private func alert(_ buttons: [String]) -> some View {
        VStack(spacing: 10) {
            ForEach(buttons, id: \.self) { cardButton($0, isProminent: $0 == buttons.first) }
        }
        .padding(.vertical, 14)
    }

    private func cardButton(_ title: String, isProminent: Bool) -> some View {
        Button {
            actions.alertAction(title)
        } label: {
            Text(title).font(.body.weight(.medium)).frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.borderedProminent)
        .tint(isProminent ? Color.auraGreen : .white.opacity(0.2))
        .foregroundStyle(isProminent ? Color.black : Color.white)
        .padding(.horizontal, 14)
    }
}

/// Manual: X and Y at the top left, the ladybug at the top right, four round green arrows, and
/// a small icon at the bottom right for the step size and the arrow direction. The arrows are
/// the Stage hand pad's own (`HandArrowButton`).
struct ScanManualPad: View {
    var state: ScanPageState
    var actions: ScanPageActions

    var body: some View {
        VStack(spacing: 6) {
            arrow(.up)
            HStack(spacing: 74) {
                arrow(.left)
                arrow(.right)
            }
            arrow(.down)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 2) {
                Text("X: \(state.pad.x)°")
                Text("Y: \(state.pad.y)°")
            }
            .font(.subheadline.monospacedDigit())
            .padding(12)
        }
        .overlay(alignment: .topTrailing) {
            ScanLadybugButton(showsBoxes: state.showsBoxes, action: actions.toggleBoxes)
                .padding(10)
        }
        .overlay(alignment: .bottomTrailing) {
            Button(action: actions.openPadSettings) {
                Image(systemName: "slider.horizontal.3").font(.body)
                    .frame(width: 36, height: 36)
            }
            .foregroundStyle(.white.opacity(0.8))
            .accessibilityLabel(state.pad.canFineStep ? "Step size and arrow direction" : "Arrow direction")
            .padding(8)
        }
    }

    private func arrow(_ arrow: StageArrow) -> some View {
        HandArrowButton(
            arrow: arrow, isEnabled: state.pad.isEnabled(arrow),
            onPress: { actions.press(arrow) }, onRelease: { actions.release(arrow) },
            diameter: 52, isGreen: true)
    }
}
