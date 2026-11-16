import Foundation

/// Where the slide movement lab registers movement.
enum FieldRegionMode: String, CaseIterable, Identifiable {
    /// Learned once at the start of the session from several frames: the dark parts joined to
    /// the frame's border are the eyepiece, and movement is measured in the open field.
    case auto
    /// One frame: grayscale, an automatic light/dark cut, the largest connected bright region
    /// is the field, and movement is measured inside it. No learning over time.
    case brightRegion
    /// Always the centred fallback square.
    case centreSquare
    /// The old behaviour, for comparison.
    case wholeFrame

    var id: String { rawValue }

    /// Whether the mode works out the field from the camera's frames.
    var learnsMask: Bool { self == .auto || self == .brightRegion }

    var title: String {
        switch self {
        case .auto: "Auto (learned once)"
        case .brightRegion: "Bright region (one frame)"
        case .centreSquare: "Centre square"
        case .wholeFrame: "Whole frame"
        }
    }

    /// The word written in the CSV. For Auto the pipeline writes "auto-learned" or
    /// "auto-untrusted" instead, once the mask is decided.
    var csvName: String {
        switch self {
        case .auto: "auto"
        case .brightRegion: "bright-region"
        case .centreSquare: "centre-square"
        case .wholeFrame: "whole-frame"
        }
    }
}
