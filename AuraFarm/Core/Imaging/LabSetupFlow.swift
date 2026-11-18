import Foundation

enum LabSetupStep: Equatable {
    case align, focus, field, stage, done

    /// Later steps are higher; for telling forward moves from a redo.
    var order: Int {
        switch self {
        case .align: 0
        case .field: 1
        case .focus: 2
        case .stage: 3
        case .done: 4
        }
    }

    /// A short word for the CSV.
    var csvName: String {
        switch self {
        case .align: "align"
        case .focus: "focus"
        case .field: "field"
        case .stage: "stage"
        case .done: "done"
        }
    }
}

/// The order of a lab session's setup: 1 align the phone, 2 field (find the eyepiece: learn,
/// review and confirm the round view), 3 focus (with the confirmed field), 4 stage (measure the
/// two knobs' axes), then the lab itself. It only holds the step; the caller feeds it what the
/// checks say.
///
/// Losing alignment after it passed (`alignmentLost`), at field, focus or stage, sends it back
/// to align and then to FIELD, because the circle moved and the mask must be learned again;
/// focus follows as usual.
struct LabSetupFlow: Equatable {
    /// How many steps the indicator shows.
    static let stepCount = 4

    private(set) var step: LabSetupStep
    /// Where to go when align passes again after `alignmentLost`; nil in an ordinary run.
    private(set) var resumeStep: LabSetupStep?
    /// The helper chose to skip align and focus: the field step still runs, and goes straight to
    /// stage once confirmed.
    private var skipsFocus: Bool

    /// Starts at align, or at field when the helper chose to skip align and focus.
    init(skippingAlignAndFocus: Bool = false) {
        step = skippingAlignAndFocus ? .field : .align
        skipsFocus = skippingAlignAndFocus
    }

    /// 1, 2 or 3 for the indicator; done shows the last step as complete.
    var stepNumber: Int {
        switch step {
        case .align: 1
        case .field: 2
        case .focus: 3
        case .stage, .done: 4
        }
    }

    var isDone: Bool { step == .done }

    /// Moves on when the current step's condition holds, at most one step per call. Returns
    /// whether the step changed.
    /// - Parameters:
    ///   - alignmentPassed: `AlignmentCheck.isPassed`.
    ///   - focused: `FocusGuide` reached `focused`.
    ///   - fieldConfirmed: the field is learned and the person confirmed it.
    ///   - stageMeasured: `StageAxesCalibration` is done.
    @discardableResult
    mutating func update(
        alignmentPassed: Bool = false, focused: Bool = false, fieldConfirmed: Bool = false,
        stageMeasured: Bool = false
    ) -> Bool {
        switch step {
        case .align where alignmentPassed:
            step = resumeStep ?? .field
            resumeStep = nil
        case .field where fieldConfirmed: step = skipsFocus ? .stage : .focus
        case .focus where focused: step = .stage
        case .stage where stageMeasured: step = .done
        default: return false
        }
        return true
    }

    /// Alignment was lost after it passed: back to align, remembering where it was. The field
    /// and stage steps are remembered as FIELD. Nothing happens at align or when done (the run
    /// monitor watches then).
    mutating func alignmentLost() {
        switch step {
        case .field, .focus, .stage: resumeStep = .field
        case .align, .done: return
        }
        step = .align
    }

    /// All of it again, from align.
    mutating func redo() {
        step = .align
        resumeStep = nil
        skipsFocus = false
    }

    /// Only the field again.
    mutating func redoField() {
        step = .field
        resumeStep = nil
    }

    /// Straight to the lab (on the stage step, with `StageAxes.identity`).
    mutating func skip() {
        step = .done
        resumeStep = nil
    }
}
