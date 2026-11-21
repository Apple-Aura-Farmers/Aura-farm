#if DEBUG
    import SwiftUI

    /// The automated stage's controls, above the lab's camera view. Buttons and pickers only.
    struct AutoStagePanel: View {
        let driver: AutoStageDriver
        let setupStep: LabSetupStep

        var body: some View {
            @Bindable var driver = driver
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Circle().fill(dot).frame(width: 10, height: 10)
                    Text(phaseText).font(.footnote).lineLimit(2)
                    Spacer()
                    if driver.client.status == .connected || driver.client.status == .reconnecting {
                        Button("Disconnect") { driver.client.disconnect() }
                    } else {
                        Button("Connect") { driver.client.connect() }
                    }
                }
                if !driver.mappingSummary.isEmpty {
                    Text(driver.mappingSummary).font(.caption).foregroundStyle(.secondary)
                }
                Picker("Chunk", selection: $driver.chunkDegrees) {
                    ForEach([1, 2, 3, 5, 10], id: \.self) { Text("\($0)°").tag($0) }
                }
                .pickerStyle(.segmented)
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
                if case .failed = driver.phase {
                    Button("Retry") { driver.recalibrate() }.buttonStyle(.borderedProminent)
                        .disabled(setupStep != .stage && setupStep != .done)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 6)
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
            case .calibrating(let axis, let travel):
                String(format: "Calibrating servo %@: %.1f fields", axis.letter, travel)
            case .calibrated: "Calibrated"
            case .following: "Following the guide" + (driver.lastMove.isEmpty ? "" : " (\(driver.lastMove))")
            case .waitingForEdgeAnswer: "Stopped: answer the edge question"
            case .atLimit(let servo):
                "Servo \(servo.letter) reached its limit; press Stage limit if the edge can't be reached"
            case .paused: "Paused"
            case .failed(let message): message
            }
        }
    }
#endif
