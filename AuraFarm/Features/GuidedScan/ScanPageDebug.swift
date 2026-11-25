#if DEBUG
    import SwiftUI

    // The Debug state picker for the Scan page: every state built by hand from fake values. Nothing
    // here touches the camera, the engine, the driver or Bluetooth: the only thing that leaves it
    // is `onClose`. Not in Release builds.

    enum ScanScenario: String, CaseIterable, Identifiable {
        case movingWithOrganisms, movingNone, movingToStart, crossingEmpty, paused, pausedGoesBack
        case endingAfterColumn
        case focusFar, focusNear, focusSharp, focusWrongWay, focusNoDial, focusEmptyArea
        case phoneMoved, disconnected, restarted, noSampleFound, tooHot
        case switchingToManual, manualSwitchFailed, manual, manualCheckFocus, manualLimitNote
        case goingBack, checkingFocus, complete, loading

        var id: Self { self }

        var title: String {
            switch self {
            case .movingWithOrganisms: "Moving with organisms"
            case .movingNone: "Moving, none found"
            case .movingToStart: "Moving to start"
            case .crossingEmpty: "Crossing empty"
            case .paused: "Paused"
            case .pausedGoesBack: "Paused, goes back first"
            case .endingAfterColumn: "Ending after column"
            case .focusFar: "Focus issue: far off"
            case .focusNear: "Focus issue: near"
            case .focusSharp: "Focus issue: sharp"
            case .focusWrongWay: "Focus issue: wrong way"
            case .focusNoDial: "Focus issue: no dial"
            case .focusEmptyArea: "Focus issue: with empty-area button"
            case .phoneMoved: "Phone moved"
            case .disconnected: "Disconnected"
            case .restarted: "Restarted"
            case .noSampleFound: "No sample found"
            case .tooHot: "Too hot"
            case .switchingToManual: "Switching to manual"
            case .manualSwitchFailed: "Manual switch failed"
            case .manual: "Manual"
            case .manualCheckFocus: "Manual, check focus"
            case .manualLimitNote: "Manual, stage limit note"
            case .goingBack: "Going back"
            case .checkingFocus: "Checking focus"
            case .complete: "Complete"
            case .loading: "Loading"
            }
        }
    }

    /// What the sheet sets besides the state.
    struct ScanPreviewOptions: Equatable {
        var progress = 0.3
        var boxesOn = true
        /// 0 to 12 kinds found.
        var kindCount = 3
        var longFarmName = false
        var isOwnSample = false
        var x = 58
        var y = 138
    }

    extension ScanScenario {
        static let kindNames = [
            "Ciliates", "Amoebae", "Nematodes", "Euglenoids", "Algae", "Other protists",
            "Bdelloid rotifers", "Monogonont rotifers", "Not sorted yet", "Tardigrades", "Mites",
            "Springtails",
        ]

        /// The page's input for this state: a value, built by hand.
        func input(_ o: ScanPreviewOptions) -> ScanPageInput {
            var i = ScanPageInput()
            i.sampleID =
                o.isOwnSample
                ? "My own sample"
                : (o.longFarmName ? "Koperasi Tani Makmur Sejahtera Bersama Desa Pak Wayan" : "Pak Wayan")
            i.plotName = o.isOwnSample ? nil : "Plot 1"
            i.isOwnSample = o.isOwnSample
            i.fraction = o.progress
            i.showsBoxes = o.boxesOn
            i.pad = ScanPad(x: o.x, y: o.y, canFineStep: true)
            i.canChangeMode = true
            i.columnInProgress = true
            let kinds = min(max(o.kindCount, 0), Self.kindNames.count)
            i.found = (0..<kinds).map { ScanFoundRow(name: Self.kindNames[$0], count: 24 - 2 * $0) }

            var s = ScanStageInput()
            s.phase = .presetPath(column: 7, spot: 7)
            s.connectionText = AutoStageStatus.connectionText(.idle)
            let dial = { (offset: Double, side: FocusDialSide, green: Bool, wrong: Bool, text: String) in
                FocusDialReading(
                    offset: offset, side: side, greenHalfWidth: 0.2, isGreen: green,
                    isWrongWay: wrong, message: text)
            }
            switch self {
            case .movingWithOrganisms: break
            case .movingNone: i.found = []
            case .movingToStart: s.phase = .presetPath(column: 0, spot: 0)
            case .crossingEmpty: s.phase = .crossingEmpty(fields: 1.5)
            case .paused: s.phase = .paused
            case .pausedGoesBack:
                s.phase = .paused
                i.goesBackFirst = true
            case .endingAfterColumn: i.endingAfterColumn = true
            case .focusFar, .focusEmptyArea:
                s.alert = .focusPause
                s.dial = dial(-0.8, .approaching, false, false, "Not far enough. Keep turning.")
                s.canConfirmEmptyArea = self == .focusEmptyArea
            case .focusNear:
                s.alert = .focusPause
                s.dial = dial(-0.3, .approaching, false, false, "Almost there.")
                s.focusHint = "Turn the focus knob a little further."
            case .focusSharp:
                s.alert = .focusPause
                s.dial = dial(0.05, .approaching, true, false, "Sharp ✓ Hold still")
            case .focusWrongWay:
                s.alert = .focusPause
                s.dial = dial(0.6, .past, false, true, "Other way.")
            case .focusNoDial: s.alert = .focusPause
            case .phoneMoved: s.alignmentPaused = true
            case .disconnected:
                s.alert = .disconnected
                s.alertButtons = ["Retry"]
            case .restarted:
                s.phase = .paused
                s.alert = .stageRestarted
                s.alertButtons = ["Resume"]
            case .noSampleFound:
                s.phase = .emptyCapReached(fields: 2)
                s.alert = .emptyCapReached
                s.alertButtons = ["Keep crossing", "End column here"]
            case .tooHot: s.isTooHot = true
            case .switchingToManual:
                s.phase = .paused
                s.isSwitchingToManual = true
            case .manualSwitchFailed:
                s.phase = .paused
                s.manualSwitchProblem = "The stage did not answer. Try again."
            case .manual: s.phase = .byHand
            case .manualCheckFocus:
                s.phase = .byHand
                s.handFocusReminder = true
            case .manualLimitNote:
                s.phase = .byHand
                s.handNote = "Reached the end of the stage's range."
            case .goingBack: s.phase = .returningFromHand(x: 58, y: 138)
            case .checkingFocus: s.phase = .checkingFocus
            case .complete, .loading:
                s.isComplete = true
                i.fraction = 1
                i.isFinished = true
                i.showsLoading = self == .loading
            }
            switch s.phase {
            case .byHand, .returningFromHand, .checkingFocus: i.isAwayFromPath = true
            default: break
            }
            i.isPaused = s.phase == .paused
            i.stage = s
            return i
        }
    }

    /// The fake state and the fake actions. Each one changes what is shown or does nothing; ending
    /// and discarding only close the page. There is no engine or driver here to call.
    @MainActor @Observable
    final class ScanPreviewModel {
        var scenario = ScanScenario.movingWithOrganisms
        var options = ScanPreviewOptions()
        var hidesButton = false
        @ObservationIgnored private let onClose: () -> Void

        init(onClose: @escaping () -> Void) { self.onClose = onClose }

        var state: ScanPageState { .make(scenario.input(options)) }

        var actions: ScanPageActions {
            var a = ScanPageActions()
            a.close = { [self] in onClose() }
            a.togglePause = { [self] in
                switch scenario {
                case .paused, .pausedGoesBack: scenario = .movingWithOrganisms
                default: scenario = .paused
                }
            }
            a.chooseEnd = { [self] item in
                switch item {
                case .endNow, .discard: onClose()  // closes without saving
                case .endAfterColumn: scenario = .endingAfterColumn
                case .undo: scenario = .movingWithOrganisms
                case .keepScanning: break
                }
            }
            a.toggleBoxes = { [self] in options.boxesOn.toggle() }
            a.setMode = { [self] mode in scenario = mode == .manual ? .manual : .movingWithOrganisms }
            a.press = { [self] arrow in
                switch arrow {
                case .up: options.y = min(options.y + 3, 180)
                case .down: options.y = max(options.y - 3, 0)
                case .right: options.x = min(options.x + 3, 180)
                case .left: options.x = max(options.x - 3, 0)
                }
            }
            a.longPressDate = { [self] in hidesButton = false }
            return a
        }
    }

    /// The Scan page from fake values, over the whole page.
    struct ScanPagePreview: View {
        @State private var model: ScanPreviewModel
        @State private var showsPicker = false

        init(onClose: @escaping () -> Void) {
            _model = State(initialValue: ScanPreviewModel(onClose: onClose))
        }

        var body: some View {
            let state = model.state
            let actions = model.actions
            ScanLayoutView(pinsToTop: true) {
                ScanTopBar(top: state.top, actions: actions, ladybug: nil).zIndex(1)
            } picture: {
                ScanPreviewLens(state: state)
            } bottom: {
                ScanBottomView(state: state, actions: actions)
            }
            .background { Color.clear.auraBackground().environment(\.colorScheme, .dark).ignoresSafeArea() }
            .background(.black)
            .foregroundStyle(.white)
            .overlay {
                if state.showsLoading { OperatorLoadingScreen().ignoresSafeArea() }
            }
            .overlay(alignment: .bottomLeading) {
                if !model.hidesButton { ScanDebugButton { showsPicker = true } }
            }
            .sheet(isPresented: $showsPicker) { ScanPreviewSheet(model: model) }
        }
    }

    /// The small hammer, clear of the design's controls.
    struct ScanDebugButton: View {
        var action: () -> Void

        var body: some View {
            Button(action: action) {
                Image(systemName: "hammer").font(.footnote)
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .foregroundStyle(.white)
            .padding(.leading, 8)
            .accessibilityLabel("Debug")
        }
    }

    /// The Microscope picture in the round view, with three sample boxes in the app's own style.
    private struct ScanPreviewLens: View {
        var state: ScanPageState

        private static let sample: LiveCountInfo = {
            var info = LiveCountInfo()
            info.boxes = [
                .init(
                    id: 1, label: "amoeba", confidence: 0.9,
                    rect: CGRect(x: 380, y: 130, width: 260, height: 200), status: .counted),
                .init(
                    id: 2, label: "amoeba", confidence: 0.8,
                    rect: CGRect(x: 530, y: 480, width: 240, height: 220), status: .seenOnce),
                .init(
                    id: 3, label: "nematode", confidence: 0.7,
                    rect: CGRect(x: 120, y: 520, width: 230, height: 260), status: .repeatOnMap),
            ]
            return info
        }()

        var body: some View {
            GeometryReader { proxy in
                // The same size as the ring's own fallback circle.
                let side = min(proxy.size.width, proxy.size.height) * 0.83
                ZStack {
                    Image("Microscope").resizable().scaledToFill()
                        // A little under the ring, so no seam shows between the picture and the ring.
                        .frame(width: side - 8, height: side - 8)
                        .overlay {
                            if state.showsBoxes {
                                GeometryReader { box in
                                    DetectionBoxes(info: Self.sample) { rect in
                                        let k = box.size.width / 1000
                                        return [
                                            CGPoint(x: rect.minX * k, y: rect.minY * k),
                                            CGPoint(x: rect.maxX * k, y: rect.minY * k),
                                            CGPoint(x: rect.maxX * k, y: rect.maxY * k),
                                            CGPoint(x: rect.minX * k, y: rect.maxY * k),
                                        ]
                                    }
                                }
                            }
                        }
                        .clipShape(Circle())
                    OperatorScanRing(
                        circle: nil, phase: state.isComplete ? .complete : .moving, showsArrow: false,
                        fraction: state.ringFraction, direction: nil, isEmpty: state.ringIsEmpty)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
        }
    }

    /// The states, the progress slider, boxes, the number of found kinds, a long farm name, an own
    /// sample, and "Hide this button". "Preview" shows here only.
    struct ScanPreviewSheet: View {
        @Bindable var model: ScanPreviewModel
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                Form {
                    Section("State") {
                        ForEach(ScanScenario.allCases) { scenario in
                            Button {
                                model.scenario = scenario
                            } label: {
                                HStack {
                                    Text(scenario.title)
                                    Spacer()
                                    if model.scenario == scenario { Image(systemName: "checkmark") }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                    Section("Options") {
                        VStack(alignment: .leading) {
                            Text("Progress \(Int(model.options.progress * 100))%")
                            Slider(value: $model.options.progress, in: 0...1)
                        }
                        Toggle("Detection boxes", isOn: $model.options.boxesOn)
                        Stepper(
                            "Kinds found: \(model.options.kindCount)",
                            value: $model.options.kindCount, in: 0...12)
                        Toggle("Long farm name", isOn: $model.options.longFarmName)
                        Toggle("Own sample", isOn: $model.options.isOwnSample)
                        Button("Hide this button") {
                            model.hidesButton = true
                            dismiss()
                        }
                        Text("A long press on the date brings the button back.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
#endif
