import Foundation

/// What a saved sweep holds. Written as JSON beside the frames so a set of stills can be
/// traced back to the sample it came from, the same way a clip's sidecar did.
struct FrameSetManifest: Codable, Equatable {
    var details: RecordingMetadata
    /// Frames actually written, which can be fewer than the sweep asked for.
    var frameCount: Int
    /// Total size of the frames on disk, in bytes.
    var byteCount: Int
    /// True when the sweep stopped on its size ceiling instead of finishing.
    var stoppedEarly: Bool
    /// The file name of the joined-up image, or nil when the frames could not be lined up.
    /// nil also for a sweep saved before panoramas existed.
    var panoramaFile: String?
    /// Why the frames could not be joined, when they could not be. The frames are kept
    /// either way: the panorama is derived, they are the raw data.
    var panoramaProblem: String?
}
