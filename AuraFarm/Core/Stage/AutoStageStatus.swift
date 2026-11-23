import Foundation

/// Something the automated stage needs the person for. The banner's words are here; the buttons
/// belong to the screen that shows it.
enum AutoStageAlert: Equatable {
    case focusPause
    case stageRestarted
    case disconnected
    case emptyCapReached
    case calibrationFailed(String)

    /// A short name for the CSV (`alert_<kind>`) and for telling one alert from another.
    var kind: String {
        switch self {
        case .focusPause: "focus_pause"
        case .stageRestarted: "stage_restarted"
        case .disconnected: "disconnected"
        case .emptyCapReached: "empty_cap_reached"
        case .calibrationFailed: "calibration_failed"
        }
    }

    var message: String {
        switch self {
        case .focusPause: "Refocus by hand, then the stage carries on."
        case .stageRestarted:
            "The stage restarted. Check its power, then tap Resume to walk it back."
        case .disconnected: "The Terraloka Stage disconnected. Reconnecting…"
        case .emptyCapReached: "Still no sample after crossing. Keep going or end this column?"
        case .calibrationFailed(let reason): "Calibration didn't work. \(reason)"
        }
    }
}

/// The automated stage in plain words: a title, an optional second line, and whether the person
/// is needed. Pure: it only reads what the driver and the Bluetooth link say.
struct AutoStageStatus: Equatable {
    var title: String
    var detail: String?
    var needsPerson: AutoStageAlert?

    /// What to say while the link is made (or cannot be).
    static func connectionText(_ status: StageBLEClient.Status) -> String {
        switch status {
        case .scanning, .connecting, .reconnecting: "Connecting to the Terraloka Stage…"
        case .bluetoothUnavailable: "Bluetooth is off. Turn it on to use the Terraloka Stage."
        case .unauthorized: "Bluetooth access is off for Terraloka. Allow it in Settings."
        case .idle: "Couldn't find the Terraloka Stage. Check it is powered on."
        case .connected: "Connected to the Terraloka Stage."
        }
    }

    /// - Parameters:
    ///   - hasConnected: the stage has been connected at least once this test, so a link that is
    ///     down now is a disconnection and not the first attempt.
    ///   - focusPaused: the run monitor holds the run for focus.
    ///   - tooHot: the phone is too hot to count, so the stage waits.
    ///   - dwelling: the preset path is standing at a spot.
    static func make(
        phase: AutoStageDriver.Phase, restartNotice: String?, presetEdgePrompt: Bool,
        pathMode: StagePathMode, client: StageBLEClient.Status, focusPaused: Bool,
        dwelling: Bool = false, hasConnected: Bool = true, tooHot: Bool = false
    ) -> AutoStageStatus {
        if let restartNotice {
            return AutoStageStatus(
                title: "The stage restarted", detail: restartNotice, needsPerson: .stageRestarted)
        }
        if client != .connected {
            if hasConnected {
                return AutoStageStatus(
                    title: "The Terraloka Stage disconnected.", detail: connectionText(client),
                    needsPerson: .disconnected)
            }
            return AutoStageStatus(title: connectionText(client), detail: nil, needsPerson: nil)
        }
        var status = AutoStageStatus(title: "", detail: nil, needsPerson: nil)
        var running = false
        switch phase {
        case .disconnected:
            status.title = connectionText(client)
        case .waitingForStageStep:
            status.title = "Getting ready to calibrate…"
        case .warmingUp(let index, let count, let title):
            status.title = "Warming up the stage (\(index) of \(count)): \(title)"
        case .calibrating(let axis, _):
            status.title = "Measuring how the stage moves (servo \(axis.letter))"
        case .calibrated, .readyToStart:
            status.title = "Stage calibrated"
        case .following:
            status.title = "Stage following the guide"
            running = true
        case .waitingForEdgeAnswer:
            status.title = "Checking an edge"
            running = true
        case .atLimit(let servo):
            status.title = "Reached the end of the stage's range"
            status.detail = "Servo \(servo.letter)"
            running = true
        case .walkingBack:
            status.title = "Walking the stage back"
        case .crossingEmpty(let fields):
            status.title = "Crossing an empty patch"
            status.detail = String(format: "%.1f fields", fields)
            running = true
        case .emptyCapReached(let fields):
            status.title = "No sample found"
            status.detail = String(format: "Still empty after %.1f fields", fields)
            status.needsPerson = .emptyCapReached
        case .presetPath(let column, let spot):
            running = true
            if presetEdgePrompt {
                status.title = "Checking an edge"
            } else if column == 0 {
                status.title = "Moving to the start corner"
            } else if dwelling {
                status.title = "Pausing at a spot"
                status.detail = "Column \(column)"
            } else {
                status.title = "Stage moving · column \(column)"
                status.detail = "Spot \(spot)"
            }
        case .paused:
            status.title = "Paused"
        case .failed(let reason):
            status.title = "Calibration didn't work"
            status.detail = reason
            status.needsPerson = .calibrationFailed(reason)
        }
        if running, focusPaused {
            status.title = "Waiting for focus"
            status.detail = nil
            status.needsPerson = .focusPause
        } else if running, tooHot {
            status.title = HelperInstruction.tooHot.text
            status.detail = "The stage waits and carries on by itself."
        }
        return status
    }
}
