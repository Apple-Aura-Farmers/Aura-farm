import CoreMedia
import Foundation

/// How fast the lab's camera runs, and which of its frames are analysed. Both give the same
/// nominal 10 analysed frames a second; 20 fps just runs the camera (and its heat) less.
enum CameraRate: String, CaseIterable, Identifiable {
    case fps20, fps30

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fps20: "20 fps"
        case .fps30: "30 fps"
        }
    }

    /// The frame rate to ask the device for; nil leaves the camera as it is (30 fps).
    var framesPerSecond: Int? { self == .fps20 ? 20 : nil }

    /// One frame in this many is analysed.
    var analyzeEveryNthFrame: Int { self == .fps20 ? 2 : 3 }

    /// The frame duration to set, or nil for the camera's own.
    var frameDuration: CMTime? {
        framesPerSecond.map { CMTime(value: 1, timescale: CMTimeScale($0)) }
    }
}

/// The numbers the 20 fps camera setting is made with. Data, not logic.
struct CameraRateThresholds {
    /// The longest exposure at 20 fps, so a frame is no blurrier than at 30 fps. Changing the frame
    /// duration lets the camera expose up to 1/20 s, which would blur a moving slide more.
    /// PLACEHOLDER: a shorter exposure means less blur and more noise; the 30 fps setting removes
    /// the cap.
    var maxExposureSeconds = 1.0 / 30
}
