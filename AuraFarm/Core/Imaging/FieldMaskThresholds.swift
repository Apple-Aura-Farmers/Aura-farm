import Foundation

/// The numbers `FieldMaskBuilder` learns the eyepiece mask with. Data, not logic.
struct FieldMaskThresholds {
    /// Sample the luma every this many pixels in each direction for the mask grid.
    /// PLACEHOLDER: not calibrated.
    var gridStep: Int = 8
    /// Frames collected before the mask is decided (about 3 s at 10 analyzed frames a
    /// second, long enough to move the slide around). PLACEHOLDER: not calibrated.
    var framesToLearn: Int = 30
    /// Each frame is split into dark and bright by an automatic (Otsu) cut. If the bright
    /// side's mean is not at least this many times the dark side's, the frame has no dark
    /// part (evenly lit). PLACEHOLDER: not calibrated.
    var minContrastRatio: Double = 2
    /// The automatic cut is multiplied by this, so the lens's dimmer rim (between the dark
    /// surround and the bright middle) still counts as field. PLACEHOLDER: not calibrated.
    var cutScale: Double = 0.6
    /// A cell counts as eyepiece when it was dark in at least this share of the frames.
    /// PLACEHOLDER: not calibrated.
    var alwaysDarkShare: Double = 0.95
    /// The registration rectangle is shrunk by this share of its width and height on each
    /// side, so the ring's soft edge stays out. PLACEHOLDER: not calibrated.
    var insetShare: Double = 0.06
    /// When the open field is smaller than this share of the frame, the mask is not trusted.
    /// PLACEHOLDER: not calibrated.
    var minOpenShare: Double = 0.15
}
