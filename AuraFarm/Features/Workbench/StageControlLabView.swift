#if DEBUG
    import SwiftUI

    /// Lab screen for driving the Terraloka stage over Bluetooth. No text entry: buttons, sliders
    /// and the pad only. Debug builds only, from the workbench.
    struct StageControlLabView: View {
        @State private var client = StageBLEClient()
        @AppStorage("stageLab.flipX") private var flipX = false
        @AppStorage("stageLab.flipY") private var flipY = false
        @State private var step = 5
        @State private var dragTarget: StagePoint?
        @State private var path: [StagePoint] = []
        @State private var sliderX = 90.0
        @State private var sliderY = 90.0
        @State private var sliderZ = 90.0
        @State private var pathNote: String?

        private var connected: Bool { client.status == .connected }
        private var manualOn: Bool { connected && client.mode == .manual }
        private var autoOn: Bool { connected && client.mode == .auto }
        private var busy: Bool { client.runState != .idle || client.queued > 0 }

        var body: some View {
            ScrollView {
                VStack(spacing: 16) {
                    connectionRow
                    modePicker
                    StagePadView(
                        current: StagePoint(x: client.x, y: client.y),
                        target: client.mode == .manual ? dragTarget : nil,
                        path: client.mode == .auto ? path : [],
                        flipX: flipX, flipY: flipY, onTouch: padTouch
                    )
                    if let t = dragTarget, client.mode == .manual {
                        Text("Target X \(t.x)°  Y \(t.y)°").font(.callout.monospacedDigit())
                    }
                    Text("Stage X \(client.x)°  Y \(client.y)°  \(String(describing: client.runState))")
                        .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                    HStack {
                        Toggle("Flip X", isOn: $flipX)
                        Toggle("Flip Y", isOn: $flipY)
                    }
                    manualControls
                    focusControls
                    autoControls
                    alwaysControls
                    if let e = client.lastError { Text(e).foregroundStyle(.red) }
                    logSection
                }
                .padding()
            }
            .navigationTitle("Stage control")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: client.x) { _, v in sliderX = Double(v) }
            .onChange(of: client.y) { _, v in sliderY = Double(v) }
            .onChange(of: client.z) { _, v in if let v { sliderZ = Double(v) } }
            .onDisappear { client.disconnect() }
        }

        // MARK: Sections

        private var connectionRow: some View {
            HStack {
                Circle().fill(dotColor).frame(width: 12, height: 12)
                Text(statusText)
                Spacer()
                if client.status == .idle || client.status == .bluetoothUnavailable
                    || client.status == .unauthorized
                {
                    Button("Connect") { client.connect() }.buttonStyle(.borderedProminent)
                } else {
                    Button("Disconnect") { client.disconnect() }.buttonStyle(.bordered)
                }
            }
        }

        private var modePicker: some View {
            Picker(
                "Mode",
                selection: Binding(
                    get: { client.mode },
                    set: { client.send(.mode($0)) }
                )
            ) {
                Text("Manual").tag(StageMode.manual)
                Text("Auto").tag(StageMode.auto)
            }
            .pickerStyle(.segmented)
            .disabled(!connected || busy)
        }

        private var manualControls: some View {
            GroupBox("Manual") {
                VStack(spacing: 12) {
                    slider("X", value: $sliderX)
                    slider("Y", value: $sliderY)
                    Picker("Step", selection: $step) {
                        ForEach([1, 5, 10], id: \.self) { Text("\($0)°").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    HStack(spacing: 12) {
                        arrow("arrow.left") { client.jog(.x, flipX ? step : -step) }
                        arrow("arrow.right") { client.jog(.x, flipX ? -step : step) }
                        arrow("arrow.down") { client.jog(.y, flipY ? step : -step) }
                        arrow("arrow.up") { client.jog(.y, flipY ? -step : step) }
                    }
                }
            }
            .disabled(!manualOn)
        }

        private var focusControls: some View {
            GroupBox("Focus (Z)") {
                VStack(spacing: 12) {
                    Text(client.z.map { "Z: \($0)°" } ?? "Z: not reported (old firmware)")
                        .font(.callout.monospacedDigit())
                    HStack(spacing: 12) {
                        ForEach([-5, -1, 1, 5], id: \.self) { delta in
                            Button(delta > 0 ? "+\(delta)" : "\(delta)") { client.jogFocus(delta) }
                                .buttonStyle(.bordered)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    HStack {
                        Text("\(Int(sliderZ))°").monospacedDigit().frame(
                            width: 70, alignment: .leading)
                        Slider(value: $sliderZ, in: 0...180, step: 1) { editing in
                            if !editing { client.moveFocus(to: Int(sliderZ)) }
                        }
                    }
                    Text("Free-spinning test: the servo is not on the focus knob yet")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .disabled(!manualOn)
        }

        private var autoControls: some View {
            GroupBox("Auto") {
                VStack(spacing: 12) {
                    HStack {
                        Button("Traverse") { client.send(.traverse) }
                        ForEach(StagePresetPath.allCases, id: \.self) { preset in
                            Button(preset.title) { client.runPath(preset.points) }
                        }
                    }
                    .buttonStyle(.bordered)
                    Text("\(path.count) points — tap the pad to add").font(.footnote)
                    if let n = pathNote { Text(n).font(.footnote).foregroundStyle(.orange) }
                    HStack {
                        Button("Undo point") {
                            _ = path.popLast()
                            pathNote = nil
                        }
                        .disabled(path.isEmpty)
                        Button("Clear") {
                            path = []
                            pathNote = nil
                        }.disabled(path.isEmpty)
                        Button("Run path") { client.runPath(path) }
                            .buttonStyle(.borderedProminent).disabled(path.isEmpty)
                    }
                    .buttonStyle(.bordered)
                    HStack {
                        Button("Stop") { client.send(.stop) }
                        Button("Resume") { client.send(.resume) }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .disabled(!autoOn)
        }

        private var alwaysControls: some View {
            HStack(spacing: 12) {
                Button {
                    client.send(.stop)
                } label: {
                    big("Stop")
                }.tint(.red)
                Button {
                    client.send(.home)
                } label: {
                    big("Home")
                }
                Button {
                    client.send(.end)
                } label: {
                    big("End session")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!connected)
        }

        private var logSection: some View {
            DisclosureGroup("Log") {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(client.log) { line in
                        Text("\(line.date.formatted(date: .omitted, time: .standard)) \(line.text)")
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }

        // MARK: Pieces

        private func big(_ title: String) -> some View {
            Text(title).font(.headline).frame(maxWidth: .infinity, minHeight: 44)
        }

        private func arrow(_ symbol: String, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Image(systemName: symbol).frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.bordered)
        }

        private func slider(_ name: String, value: Binding<Double>) -> some View {
            HStack {
                Text("\(name) \(Int(value.wrappedValue))°").monospacedDigit().frame(
                    width: 70, alignment: .leading)
                Slider(value: value, in: 0...180, step: 1) { editing in
                    if !editing {
                        client.moveTo(x: Int(sliderX), y: Int(sliderY))
                    }
                }
            }
        }

        private func padTouch(_ point: StagePoint, ended: Bool) {
            if client.mode == .manual {
                guard manualOn else { return }
                dragTarget = point
                if ended {
                    client.moveTo(x: point.x, y: point.y)
                    dragTarget = nil
                }
            } else if ended, autoOn {
                if StageCommand.pathFits(path + [point]) {
                    path.append(point)
                    pathNote = nil
                } else {
                    pathNote = "Path is full — the device accepts about 29 points."
                }
            }
        }

        private var statusText: String {
            switch client.status {
            case .bluetoothUnavailable: "Bluetooth off or unavailable"
            case .unauthorized: "Bluetooth not allowed (Settings)"
            case .idle: "Not connected"
            case .scanning: "Scanning…"
            case .connecting: "Connecting…"
            case .connected: "Connected"
            case .reconnecting: "Reconnecting…"
            }
        }

        private var dotColor: Color {
            switch client.status {
            case .connected: .green
            case .scanning, .connecting, .reconnecting: .orange
            default: .red
            }
        }
    }
#endif
