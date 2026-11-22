#if DEBUG
    import SwiftUI

    /// The automated stage's controls, above the lab's camera view. Buttons and pickers only.
    struct AutoStagePanel: View {
        let driver: AutoStageDriver
        let setupStep: LabSetupStep
        @State private var isChangingObjective = false

        var body: some View {
            @Bindable var driver = driver
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Circle().fill(dot).frame(width: 10, height: 10)
                    Text(phaseText).font(.footnote).lineLimit(2)
                    Text(driver.objective.title).font(.footnote.bold())
                    Button("Change") { isChangingObjective = true }
                        .font(.caption)
                        .disabled(busyMeasuring)
                    Spacer()
                    if driver.client.status == .connected || driver.client.status == .reconnecting {
                        Button("Disconnect") { driver.client.disconnect() }
                    } else {
                        Button("Connect") { driver.client.connect() }
                    }
                }
                if !driver.mappingSummary.isEmpty || driver.autoStageLimitCount > 0 {
                    Text(
                        driver.mappingSummary
                            + (driver.autoStageLimitCount > 0
                                ? " · auto limits: \(driver.autoStageLimitCount)" : "")
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
                Picker("Warm-up", selection: $driver.warmUp) {
                    Text("Off").tag(StagePresetPath?.none)
                    ForEach(StagePresetPath.allCases, id: \.self) {
                        Text($0.title).tag(Optional($0))
                    }
                }
                .pickerStyle(.menu)
                .font(.footnote)
                .disabled(busyMeasuring)
                Toggle("Auto stage limit", isOn: $driver.autoStageLimit).font(.footnote)
                Picker("Chunk", selection: $driver.chunkDegrees) {
                    ForEach([1, 2, 3, 5, 10].filter { $0 >= driver.objective.minChunk }, id: \.self) {
                        Text("\($0)°").tag($0)
                    }
                }
                .pickerStyle(.segmented)
                Picker(
                    "Path",
                    selection: Binding(
                        get: { driver.pathMode }, set: { driver.setPathMode($0) })
                ) {
                    ForEach(StagePathMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!canChangePathMode)
                if driver.pathMode == .presetPath {
                    Stepper(value: $driver.dwellSeconds, in: 0.6...3.0, step: 0.2) {
                        Text(String(format: "Dwell %.1f s", driver.dwellSeconds)).font(.footnote)
                    }
                }
                if driver.presetEdgePrompt {
                    HStack {
                        Text("Edge?").font(.footnote.bold())
                        Button("Edge here") { driver.edgeHere() }
                            .buttonStyle(.borderedProminent)
                        Button("Keep going") { driver.keepGoingPastEdge() }
                            .buttonStyle(.bordered)
                    }
                }
                if let notice = driver.restartNotice {
                    Text(notice).font(.caption).foregroundStyle(.orange)
                }
                if let warning = driver.objective.warning(forChunk: driver.chunkDegrees) {
                    Text(warning).font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    if case .paused = driver.phase {
                        Button("Resume") { driver.resume() }
                    } else {
                        Button("Pause") { driver.pause() }
                    }
                    Button("Recalibrate") { driver.recalibrate() }
                        .disabled(setupStep != .stage && setupStep != .done)
                    Button("End session") { driver.endSession() }
                }
                .buttonStyle(.bordered)
                if let error = driver.client.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                if case .emptyCapReached = driver.phase {
                    HStack {
                        Button("End column here") { driver.endColumnHere() }
                            .buttonStyle(.borderedProminent)
                        Button("Keep going") { driver.keepCrossing() }
                            .buttonStyle(.bordered)
                    }
                }
                if case .failed = driver.phase {
                    Button("Retry") { driver.recalibrate() }.buttonStyle(.borderedProminent)
                        .disabled(setupStep != .stage && setupStep != .done)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 6)
            .confirmationDialog("Which objective are you using?", isPresented: $isChangingObjective) {
                ForEach(StageObjective.allCases, id: \.self) { objective in
                    Button(objective.title) { driver.changeObjective(to: objective) }
                }
            }
        }

        /// Only while paused, or before setup is done and nothing is being measured.
        private var canChangePathMode: Bool {
            switch driver.phase {
            case .paused: true
            case .disconnected, .waitingForStageStep, .failed: setupStep != .done
            default: false
            }
        }

        /// Calibrating: the objective cannot change now.
        private var busyMeasuring: Bool {
            switch driver.phase {
            case .warmingUp, .calibrating: true
            default: false
            }
        }

        private var dot: Color {
            switch driver.client.status {
            case .connected: .green
            case .scanning, .connecting, .reconnecting: .orange
            default: .red
            }
        }

        private var phaseText: String {
            switch driver.phase {
            case .disconnected: "Stage not connected"
            case .waitingForStageStep: "Connected. Waiting for the stage step"
            case .warmingUp(let title): "Warming up: \(title)"
            case .calibrating(let axis, let travel):
                String(format: "Calibrating servo %@: %.1f fields", axis.letter, travel)
            case .calibrated: "Calibrated"
            case .following: "Following the guide" + (driver.lastMove.isEmpty ? "" : " (\(driver.lastMove))")
            case .waitingForEdgeAnswer: "Stopped: answer the edge question"
            case .atLimit(let servo):
                driver.autoStageLimit
                    ? "Servo \(servo.letter) at its limit, telling the guide"
                    : "Servo \(servo.letter) reached its limit; press Stage limit if the edge can't be reached"
            case .walkingBack(let x, let y): "Walking the stage back to \(x),\(y)"
            case .crossingEmpty(let fields):
                String(format: "Crossing empty area: %.1f of %.1f fields", fields, driver.blindCap)
            case .emptyCapReached(let fields):
                String(format: "Still empty after %.1f fields", fields)
            case .presetPath(let column, let spot):
                "Preset path: column \(column), spot \(spot)"
            case .paused: "Paused"
            case .failed(let message): message
            }
        }
    }
#endif
