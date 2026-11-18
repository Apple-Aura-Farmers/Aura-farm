import Foundation

/// How the page shows the camera picture at a setup step.
struct GuidedScanPictureTreatment: Equatable {
    /// The picture is cropped and centred on the learned field (the lab does this from the stage
    /// step on, once the field is confirmed).
    var centres: Bool
    /// Everything outside the round view is dark (only with `centres`).
    var darkensOutside: Bool
    /// A fixed circle or outline for the operator to match. Never: the picture is shown whole.
    var drawsTargetOutline: Bool
}

/// Where the guided scan page is in its setup, in the page's words. The setup itself is the lab's
/// (`LabSetupFlow` through `LabSetupSession`): this only names its steps for a helper. There is no
/// stage of its own: the page starts the camera and the setup together, as the lab does.
enum GuidedScanSetupStage: Equatable, CaseIterable {
    case align, focus, field
    /// The optional knob step.
    case stage
    /// Setup is done: choose the coverage and start the scan.
    case ready

    /// How many steps the indicator counts (the lab's four).
    static let stepCount = LabSetupFlow.stepCount

    /// The page's stage for the lab's step.
    static func current(step: LabSetupStep) -> GuidedScanSetupStage {
        switch step {
        case .align: .align
        case .focus: .focus
        case .field: .field
        case .stage: .stage
        case .done: .ready
        }
    }

    /// 1 to 4; nil when setup is done.
    var number: Int? {
        switch self {
        case .align: 1
        case .focus: 2
        case .field: 3
        case .stage: 4
        case .ready: nil
        }
    }

    /// The step's name.
    var title: String {
        switch self {
        case .align: "Align"
        case .focus: "Focus"
        case .field: "Check the outline"
        case .stage: "Knobs (optional)"
        case .ready: "Ready"
        }
    }

    /// "Step 1 of 4: Align", or "Ready" when setup is done.
    var indicator: String {
        number.map { "Step \($0) of \(Self.stepCount): \(title)" } ?? "Ready"
    }

    /// One plain sentence.
    var sentence: String {
        switch self {
        case .align:
            "Move the phone until the whole round view is inside the picture, round and evenly lit."
        case .focus: "Turn the microscope's focus knob slowly until the picture is sharp."
        case .field: "Check the outline fits the round view, then confirm."
        case .stage:
            "Turn the bottom knob a little, then the top knob, as asked. You can skip this."
        case .ready: "Choose how much of the slide, then start the scan."
        }
    }

    /// How the picture is shown. Cropping and centring start where the lab starts them, after the
    /// field is confirmed; before that the whole camera picture is shown, with no target.
    var treatment: GuidedScanPictureTreatment {
        switch self {
        case .align, .focus, .field:
            GuidedScanPictureTreatment(centres: false, darkensOutside: false, drawsTargetOutline: false)
        case .stage, .ready:
            GuidedScanPictureTreatment(centres: true, darkensOutside: true, drawsTargetOutline: false)
        }
    }
}

/// The align step's checks as ticks, from the lab's own alignment reading. The lab's limits and
/// its pass rule decide (`AlignmentCheck`); this only splits `problems` into four plain lines.
struct AlignmentTicks: Equatable {
    var wholeCircleInView: Bool
    var round: Bool
    var evenlyLit: Bool
    var noGlare: Bool
    /// The lab's own verdict: every check passed long enough (`LabSetupInfo.isAlignmentPassed`).
    var passed: Bool

    init(reading: AlignmentReading, passed: Bool) {
        let seen = reading.found
        wholeCircleInView = seen && !reading.problems.contains(.clipped)
        round = seen && !reading.problems.contains(.notRound)
        evenlyLit = seen && !reading.problems.contains(.uneven)
        noGlare = seen && !reading.problems.contains(.glare)
        self.passed = passed
    }

    /// The lines in order, with their words.
    var lines: [(text: String, isOK: Bool)] {
        [
            ("Whole circle in view", wholeCircleInView), ("Round", round),
            ("Evenly lit", evenlyLit), ("No glare", noGlare),
        ]
    }
}
