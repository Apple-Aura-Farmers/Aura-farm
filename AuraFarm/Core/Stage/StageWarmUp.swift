import Foundation

/// One step of the stage's warm-up, run before calibration to take up the linkage's slack.
enum StageWarmUpItem: Equatable {
    /// The firmware's own full sweep of X and Y.
    case traverse
    case preset(StagePresetPath)

    var title: String {
        switch self {
        case .traverse: "Traverse"
        case .preset(let path): path.title
        }
    }

    /// Traverse, then the 3×3 grid, then the centre cross.
    static let defaultSequence: [StageWarmUpItem] = [
        .traverse, .preset(.grid3x3), .preset(.centreCross),
    ]
}
