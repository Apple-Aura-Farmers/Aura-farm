import Foundation

/// The microscope objective the automated stage is used with. A degree of servo moves the
/// picture further at higher magnification, so the step size has to fit the objective.
enum StageObjective: String, CaseIterable {
    case x40, x100

    var title: String { self == .x40 ? "40x" : "100x" }

    var defaultChunk: Int { self == .x40 ? 3 : 1 }

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
