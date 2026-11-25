import Foundation

// The scan part of the Scan page is drawn from one plain value (`ScanPageState`) and a set of
// actions (`ScanPageActions`). The live page fills in a `ScanPageInput` from the driver and the
// engine; the Debug state picker fills one in by hand. Everything between the two is pure.

enum ScanMode: Equatable { case auto, manual }

/// The two centred lines under the lens.
struct ScanStatus: Equatable {
    var title: String
    var detail: String?
    /// The first line is orange.
    var isWarning = false
    /// Tapping the status dismisses it (the focus reminder in Manual).
    var isReminder = false
}

struct ScanFoundRow: Equatable, Identifiable {
    var name: String
    var count: Int
    var id: String { name }
}

/// What the one place under the switch shows.
enum ScanCard: Equatable {
    /// One row per kind found so far; empty says "No Organisms Detected".
    case found([ScanFoundRow])
    /// Paused for focus: the dial (when there is one), Resume anyway, and the empty-area button.
    case focus(dial: FocusDialReading?, canConfirmEmptyArea: Bool)
    /// Another alert: its own buttons, by title.
    case alert(buttons: [String])
    /// Manual: the arrow pad.
    case manualPad
}

enum ScanPauseControl: Equatable {
    case pause, resume, goBackAndResume

    var title: String {
        switch self {
        case .pause: "Pause"
        case .resume: "Resume"
        case .goBackAndResume: "Go back and resume"
        }
    }

    var symbol: String { self == .pause ? "pause.fill" : "play.fill" }
}

/// The arrow pad's readout and which arrows work.
struct ScanPad: Equatable {
    var x = 0
    var y = 0
    var up = true
    var down = true
    var left = true
    var right = true
    var canFineStep = false

    func isEnabled(_ arrow: StageArrow) -> Bool {
        switch arrow {
        case .up: up
        case .down: down
        case .left: left
        case .right: right
        }
    }
}

/// The top bar: the title, End, and Pause or Resume.
struct ScanTopState: Equatable {
    var title: String
    var date: Date
    var endLabel: String
    var endItems: [EndRunMenu.Item]
    var endEnabled: Bool
    /// nil hides it (Manual).
    var pause: ScanPauseControl?
}

struct ScanPageState: Equatable {
    var top: ScanTopState
    var mode: ScanMode
    var switchEnabled: Bool
    var status: ScanStatus
    var card: ScanCard
    /// Share of the run done, 0 to 1.
    var ringFraction: Double
    /// Manual: an empty grey track, not the green ring's minimum.
    var ringIsEmpty: Bool
    var isComplete: Bool
    var showsBoxes: Bool
    var pad: ScanPad
    /// The loading screen over the page.
    var showsLoading: Bool
}

/// Everything the page can be asked to do. The live page wires each to the call it made before;
/// the Debug picker wires them to its fake state.
struct ScanPageActions {
    var close: () -> Void = {}
    var togglePause: () -> Void = {}
    var chooseEnd: (EndRunMenu.Item) -> Void = { _ in }
    var toggleBoxes: () -> Void = {}
    var setMode: (ScanMode) -> Void = { _ in }
    var dismissReminder: () -> Void = {}
    /// An alert's button, by its title (also "Resume anyway" and "In focus – empty area").
    var alertAction: (String) -> Void = { _ in }
    var press: (StageArrow) -> Void = { _ in }
    var release: (StageArrow) -> Void = { _ in }
    var openPadSettings: () -> Void = {}
    #if DEBUG
        /// A long press on the date brings the Debug button back.
        var longPressDate: (() -> Void)?
    #endif
}

// MARK: - Inputs

/// What the stage is doing, as plain values read from the driver and the engine's monitor.
struct ScanStageInput: Equatable {
    var phase = AutoStageDriver.Phase.paused
    /// `AutoStageDriver.status.needsPerson`: it carries AutoStageStatus's order of precedence.
    var alert: AutoStageAlert?
    var isTooHot = false
    var connectionText = ""
    var isSwitchingToManual = false
    var manualSwitchProblem: String?
    var handNote = ""
    var handFocusReminder = false
    var focusHint: String?
    var dial: FocusDialReading?
    var alignmentPaused = false
    var isComplete = false
    var canConfirmEmptyArea = false
    /// The titles of the alert's buttons.
    var alertButtons: [String] = []
    /// The column the stage is in, when known.
    var column: Int?
    /// What AutoStageStatus says, for a phase the page has no words of its own for.
    var fallback = AutoStageStatus(title: "")
}

struct ScanPageInput: Equatable {
    var sampleID = ""
    var plotName: String?
    var isOwnSample = false
    var date = Date.now
    var isFinished = false
    var endingAfterColumn = false
    var columnInProgress = false
    var isAwayFromPath = false
    var isPaused = false
    var goesBackFirst = false
    var fraction = 0.0
    var showsBoxes = true
    var found: [ScanFoundRow] = []
    var canChangeMode = false
    var pad = ScanPad()
    var showsLoading = false
    var stage = ScanStageInput()
}

// MARK: - Pure functions

extension ScanPageState {
    static func make(_ i: ScanPageInput) -> ScanPageState {
        let s = i.stage
        let mode = ScanMode.of(s)
        let pause: ScanPauseControl? =
            mode == .manual ? nil : (i.isPaused ? (i.goesBackFirst ? .goBackAndResume : .resume) : .pause)
        let top = ScanTopState(
            title: ScanTitle.make(
                sampleID: i.sampleID, plotName: i.plotName, isOwnSample: i.isOwnSample),
            date: i.date, endLabel: i.endingAfterColumn ? "Ending…" : "End",
            endItems: i.isAwayFromPath
                ? EndRunMenu.awayItems
                : EndRunMenu.items(
                    columnInProgress: i.columnInProgress, endingAfterColumn: i.endingAfterColumn),
            endEnabled: !i.isFinished, pause: pause)
        return ScanPageState(
            top: top, mode: mode, switchEnabled: i.canChangeMode && !i.isFinished && !s.isSwitchingToManual,
            status: ScanStatusMaker.make(s), card: ScanCardMaker.make(s, found: i.found),
            ringFraction: i.fraction, ringIsEmpty: mode == .manual, isComplete: s.isComplete,
            showsBoxes: i.showsBoxes, pad: i.pad, showsLoading: i.showsLoading)
    }
}

extension ScanMode {
    /// Manual while steering with the arrows or while the change-over runs; Auto otherwise (also
    /// while going back and checking focus).
    static func of(_ s: ScanStageInput) -> ScanMode {
        s.phase == .byHand || s.isSwitchingToManual ? .manual : .auto
    }
}

enum ScanStatusMaker {
    /// One status at a time: AutoStageStatus's order of precedence (the stage's alerts, then too
    /// hot), then alignment, then the rest.
    static func make(_ s: ScanStageInput) -> ScanStatus {
        if s.isComplete { return ScanStatus(title: "Detection Complete") }
        switch s.alert {
        case .stageRestarted?:
            return warning("Stage Restarted", "Check its power, then tap Resume.")
        case .disconnected?: return warning("Stage Disconnected", s.connectionText)
        case .emptyCapReached?: return warning("No Sample Found", "Keep going or end this column?")
        case .focusPause?:
            return warning(
                "Focusing Issue",
                s.focusHint ?? s.dial?.message ?? "Check your focus and make sure it's clear.")
        default: break
        }
        if s.isTooHot { return warning("Phone Too Hot", "The stage waits and carries on by itself.") }
        if s.alignmentPaused { return warning("Phone Moved", HelperInstruction.phoneMoved.text) }
        if s.isSwitchingToManual { return ScanStatus(title: "Switching to Manual") }
        let moving = ScanStatus(
            title: s.column.map { "Stage Moving • Column \($0)" } ?? "Stage Moving")
        switch s.phase {
        case .presetPath(let column, let spot):
            // The same while it moves and while it dwells, so it does not flicker.
            return column == 0
                ? ScanStatus(title: "Moving to Start")
                : ScanStatus(title: "Stage Moving • Column \(column)", detail: "Spot \(spot)")
        case .following, .waitingForEdgeAnswer: return moving
        case .crossingEmpty: return ScanStatus(title: "Crossing an Empty Patch")
        case .atLimit: return ScanStatus(title: "End of Range")
        case .paused:
            if let problem = s.manualSwitchProblem { return warning("Paused", problem) }
            return ScanStatus(title: "Paused")
        case .byHand:
            if s.handFocusReminder {
                return ScanStatus(
                    title: "Check Focus", detail: "Not counted", isWarning: true, isReminder: true)
            }
            return ScanStatus(title: "Manual", detail: s.handNote.isEmpty ? "Not counted" : s.handNote)
        case .returningFromHand: return ScanStatus(title: "Going Back")
        case .checkingFocus: return ScanStatus(title: "Going Back", detail: "Checking focus")
        default: return ScanStatus(title: s.fallback.title, detail: s.fallback.detail)
        }
    }

    private static func warning(_ title: String, _ detail: String) -> ScanStatus {
        ScanStatus(title: title, detail: detail, isWarning: true)
    }
}

enum ScanCardMaker {
    static func make(_ s: ScanStageInput, found: [ScanFoundRow]) -> ScanCard {
        if s.phase == .byHand { return .manualPad }
        if s.isComplete { return .found(found) }
        switch s.alert {
        case .focusPause?: return .focus(dial: s.dial, canConfirmEmptyArea: s.canConfirmEmptyArea)
        case nil: return .found(found)
        default: return s.alertButtons.isEmpty ? .found(found) : .alert(buttons: s.alertButtons)
        }
    }
}

enum ScanFound {
    /// One row per kind from the live map counts, flattened across the groups, most first.
    static func rows(_ counts: [String: Int]) -> [ScanFoundRow] {
        SoilLifeGroup.summarize(counts).values.flatMap { $0 }
            .map { ScanFoundRow(name: $0.name, count: $0.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }
}

enum ScanTitle {
    /// "farm • plot"; only the name for an own sample; the plot is not repeated when the name
    /// already says it (a plot named "Farmer, Plot 1" after the farmer shows as "Plot 1").
    static func make(sampleID: String, plotName: String?, isOwnSample: Bool) -> String {
        let name = sampleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isOwnSample, var plot = plotName?.trimmingCharacters(in: .whitespacesAndNewlines),
            !plot.isEmpty
        else { return name }
        if name.isEmpty { return plot }
        if plot.lowercased() == name.lowercased() { return name }
        if plot.lowercased().hasPrefix(name.lowercased() + ",") {
            plot = String(plot.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespaces)
        }
        if plot.isEmpty || name.localizedCaseInsensitiveContains(plot) { return name }
        return "\(name) • \(plot)"
    }
}

enum ScanBoxes {
    /// In a run the ladybug decides, Manual included. Before a run (the look-only session) the
    /// organisms seen while steering always show.
    static func shown(showsDetections: Bool, hasStarted: Bool, handHoldOn: Bool) -> Bool {
        hasStarted ? showsDetections : showsDetections || handHoldOn
    }
}
