#if DEBUG
    import SwiftUI

    /// The automated stage's controls, above the lab's camera view. Buttons and pickers only.
    struct AutoStagePanel: View {
        let driver: AutoStageDriver
        let setupStep: LabSetupStep
        var onSwitchToAutonomous: () -> Void = {}
        @State private var isChangingObjective = false

        var body: some View {
            @Bindable var driver = driver
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Circle().fill(dot).frame(width: 10, height: 10)
                    Text(phaseText).font(.footnote).lineLimit(2)
                    Text(driver.objective.title).font(.footnote.bold())
                    Text(isManual ? "Manual" : "Autonomous").font(.footnote).foregroundStyle(.secondary)
                    Button("Change") { isChangingObjective = true }
                        .font(.caption)
                        .disabled(busyMeasuring || (isByHand && !isManual))
                    Spacer()
                    if driver.client.status == .connected || driver.client.status == .reconnecting {
                        Button("Disconnect") { driver.client.disconnect() }
                    } else {
                        Button("Connect") { driver.client.connect() }
                    }
                }
                if !isManual, !driver.mappingSummary.isEmpty || driver.autoStageLimitCount > 0 {
                    Text(
                        driver.mappingSummary
                            + (driver.autoStageLimitCount > 0
                                ? " · auto limits: \(driver.autoStageLimitCount)" : "")
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
                if !isManual {
                    Toggle(
                        "Warm-up (traverse, 3×3, cross)",
                        isOn: Binding(
                            get: { !driver.warmUpSequence.isEmpty },
                            set: { driver.warmUpSequence = $0 ? StageWarmUpItem.defaultSequence : [] })
                    )
                    .font(.footnote)
                    .disabled(busyMeasuring)
                    Toggle("Auto stage limit", isOn: $driver.autoStageLimit).font(.footnote)
                }
                Picker("Chunk", selection: $driver.chunkDegrees) {
                    ForEach([1, 2, 3, 5, 10].filter { $0 >= driver.objective.minChunk }, id: \.self) {
                        Text("\($0)°").tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isByHand && !isManual)
                if !isManual {
                    Picker(
                        "Path",
                        selection: Binding(
                            get: { driver.pathMode }, set: { driver.setPathMode($0) })
                    ) {
                        ForEach(StagePathMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!canChangePathMode || isByHand)
                }
                if !isManual, driver.pathMode == .presetPath {
                    Stepper(value: $driver.dwellSeconds, in: 0.6...3.0, step: 0.2) {
                        Text(String(format: "Dwell %.1f s", driver.dwellSeconds)).font(.footnote)
                    }
                }
                if !isManual, driver.pathMode == .presetPath, let progress = driver.presetProgress {
                    StageProgressBar(progress: progress)
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
                if driver.manualProblem == .oldPath {
                    Text("The stage still holds an old path. Go to centre clears it.")
                        .font(.caption).foregroundStyle(.orange)
                    Button("Go to centre") { driver.goToCentre() }.buttonStyle(.borderedProminent)
                } else if driver.manualProblem == .noAnswer {
                    Text("The stage did not answer").font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    if case .paused = driver.phase {
                        if isManual {
                            Button(driver.manualProblem == .noAnswer ? "Retry" : "Continue manually") {
                                driver.continueManually()
                            }
                            Button("Switch to autonomous", action: onSwitchToAutonomous)
                                .disabled(!driver.canSwitchToAutonomous)
                        } else {
                            Button("Resume") { driver.resume() }
                        }
                    } else {
                        Button("Pause") { driver.pause() }
                    }
                    if driver.canMoveByHand {
                        Button("Move manually") { driver.beginHandControl() }
                    }
                    if driver.canBackToManual {
                        Button("Back to manual") { driver.backToManual() }
                    }
                    if driver.canGoBack, !isManual {
                        Button("Go back and resume") { driver.goBackAndResume() }
                    }
                    if !isManual {
                        Button("Recalibrate") { driver.recalibrate() }
                            .disabled((setupStep != .stage && setupStep != .done) || isByHand)
                    }
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
                if driver.phase == .waitingForFocus {
                    Button("It's sharp. Calibrate") { driver.focusIsSharp() }
                        .buttonStyle(.borderedProminent)
                }
                if case .failed = driver.phase {
                    HStack {
                        Button("Retry") { driver.recalibrate() }.buttonStyle(.borderedProminent)
                            .disabled(setupStep != .stage && setupStep != .done)
                        // Too little sample to track: preset moves need no calibration.
                        if driver.lastCalibrationFailure == .tracking {
                            Button("Use preset moves") { driver.choosePath(.presetPath) }
                                .buttonStyle(.bordered)
                        }
                    }
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
            case .disconnected, .waitingForStageStep, .waitingForFocus, .failed: setupStep != .done
            default: false
            }
        }

        private var isManual: Bool { driver.controlMode == .manual }

        /// Hand control or the way back from it: the setup is not touched meanwhile.
        private var isByHand: Bool {
            switch driver.phase {
            case .byHand, .returningFromHand, .checkingFocus, .preparingManual: true
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
            if driver.isCentring { return "Centring the stage" }
            return switch driver.phase {
            case .disconnected: "Stage not connected"
            case .waitingForStageStep: "Connected. Waiting for the stage step"
            case .warmingUp(let index, let count, let title):
                "Warming up (\(index) of \(count)): \(title)"
            case .readyToStart: "Calibrated, waiting for the run to start"
            case .calibrating(let axis, let travel):
                String(format: "Calibrating servo %@: %.1f fields", axis.letter, travel)
            case .calibrated: "Calibrated"
            case .waitingForFocus: "Focus first: the picture must be sharp to calibrate"
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
            case .choosingPath: "Choose the path"
            case .preparingManual: "Getting the stage ready"
            case .byHand:
                "Manual" + (driver.handSaved.map { " (saved \($0.x),\($0.y))" } ?? "")
            case .returningFromHand(let x, let y): "Going back to \(x),\(y)"
            case .checkingFocus: "Back in place, checking focus"
            case .failed(let message): message
            }
        }
    }
#endif
