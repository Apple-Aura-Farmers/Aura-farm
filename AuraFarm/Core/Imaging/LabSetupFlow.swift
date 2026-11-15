import Foundation

enum LabSetupStep: Equatable {
    case align, focus, field, done

    /// Later steps are higher; for telling forward moves from a redo.
    var order: Int {
        switch self {
        case .align: 0
        case .focus: 1
        case .field: 2
        case .done: 3
        }
    }

    /// A short word for the CSV.
    var csvName: String {
        switch self {
        case .align: "align"
        case .focus: "focus"
        case .field: "field"
        case .done: "done"
        }
    }
}

/// The order of a lab session's setup: 1 align the phone, 2 focus, 3 field (learn, review and
/// confirm the eyepiece field), then the lab itself. It only holds the step; the caller feeds
/// it what the checks say.
struct LabSetupFlow: Equatable {
    /// How many steps the indicator shows.
    static let stepCount = 3

    private(set) var step: LabSetupStep

    /// Starts at align, or at field when the helper chose to skip align and focus.
    init(skippingAlignAndFocus: Bool = false) {
        step = skippingAlignAndFocus ? .field : .align
    }

    /// 1, 2 or 3 for the indicator; done shows the last step as complete.
    var stepNumber: Int {
        switch step {
        case .align: 1
        case .focus: 2
        case .field, .done: 3
        }
    }

    var isDone: Bool { step == .done }

    /// Moves on when the current step's condition holds, at most one step per call. Returns
    /// whether the step changed.
    /// - Parameters:
    ///   - alignmentPassed: `AlignmentCheck.isPassed`.
    ///   - focused: `FocusGuide` reached `focused`.
    ///   - fieldConfirmed: the field is learned and the person confirmed it.
    @discardableResult
    mutating func update(
        alignmentPassed: Bool = false, focused: Bool = false, fieldConfirmed: Bool = false
    ) -> Bool {
        switch step {
        case .align where alignmentPassed: step = .focus
        case .focus where focused: step = .field
        case .field where fieldConfirmed: step = .done
        default: return false
        }
        return true
    }

    /// All of it again, from align.
    mutating func redo() { step = .align }

    /// Only the field again.
    mutating func redoField() { step = .field }

    /// Straight to the lab.
    mutating func skip() { step = .done }
}
