import Foundation

/// The microscope objective the automated stage is used with. A degree of servo moves the
/// picture further at higher magnification, so the step size has to fit the objective.
enum StageObjective: String, CaseIterable {
    case x40, x100

    var title: String { self == .x40 ? "40x" : "100x" }

    /// The smallest step (degrees) that moves the stage at all: a degree barely moves it at 100x.
    /// How far the picture moves per degree of either servo, nominally, for a preset path that
    /// is not calibrated: only the degree fallbacks use it (stop spacing without a tracked
    /// position). PLACEHOLDER: 100x from the 22 Nov runs (X 0.070 to 0.091, Y 0.047 to 0.096);
    /// 40x is the 100x value scaled by magnification, not measured.
    var nominalFieldsPerDegree: Double { self == .x100 ? 0.075 : 0.03 }

    var minChunk: Int { self == .x40 ? 1 : 2 }

    var defaultChunk: Int { self == .x40 ? 3 : 2 }

    /// The largest step (degrees) known to keep the tracker on the picture.
    var recommendedMaxChunk: Int { self == .x40 ? 3 : 2 }

    func warning(forChunk chunk: Int) -> String? {
        guard chunk > recommendedMaxChunk else { return nil }
        switch self {
        case .x40: return "Above 3°: not tried at 40x yet, tracking may slip"
        case .x100: return "Above the 2° recommended at 100x: tracking will likely slip"
        }
    }
}
