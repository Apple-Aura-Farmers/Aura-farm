import Foundation

/// The numbers the tracker uses to drop ghost frames. Data, not logic. All PLACEHOLDER.
/// Source: the 16 Nov 2026 14:20 run (soil, phone and slide still): about every 1.5 s one frame
/// read a frame-to-frame shift of about +242 px, and the next -242 px, with identical brightness
/// and contrast. The fastest real hand move logged was about 33 px a frame.
struct GhostFrameThresholds {
    /// A frame-to-frame shift larger than this share of the box side is a ghost frame: 129 px on
    /// a 322 px box, between the fastest real move and the ghosts (231 to 242 px).
    var maxFrameShiftShareOfBox = 0.4
    /// This many ghosts in a row are taken as real fast movement or a broken view: the frame
    /// then counts as having no frame-to-frame shift (the anchor stands), and the previous
    /// frame moves on.
    var maxInARow = 3
    /// A frame whose box holds fewer feature cells than this is too near empty to register:
    /// registration returns confident wrong shifts on it (38 to 53 px a frame on 16 Nov 2026
    /// 15:32, the position jumped). PLACEHOLDER. Source: the junk frames had 0 to 11 feature cells
    /// and sharpness 15 to 60, the good ones 22 to 34.
    var minFeatureCellsToRegister = 12
    /// ...and only if the box is also this blurry or flat (box sharpness under this). PLACEHOLDER.
    /// Source: the 15:32 junk frames read sharpness 15 to 60; the 22:04 dark-lighting frames
    /// wrongly skipped (feature cells read low) had a median of 370.
    var maxSharpnessForSparseSkip = 150.0
    /// This many such frames in a row go to the no-detail pause.
    var maxSparseSkipsInARow = 5
}
