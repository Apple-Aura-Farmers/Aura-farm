import Foundation

/// A problem with the live image that should stop the user from recording.
/// Declaration order is display priority: only the first active issue is shown.
enum CaptureIssue: String, CaseIterable, Identifiable, Hashable {
    case tooDark
    case blurry
    case shaky

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tooDark: return "Too dark"
        case .blurry: return "Out of focus"
        case .shaky: return "Image is shaking"
        }
    }

    /// Plain-language advice for a field helper: what to do, not what was measured.
    var advice: String {
        switch self {
        case .tooDark: return "Add more light under the slide."
        case .blurry: return "Adjust the focus until the image looks sharp."
        case .shaky: return "Hold the phone still or tighten the mount."
        }
    }

    var systemImage: String {
        switch self {
        case .tooDark: return "sun.min"
        case .blurry: return "camera.metering.unknown"
        case .shaky: return "iphone.radiowaves.left.and.right"
        }
    }
}
