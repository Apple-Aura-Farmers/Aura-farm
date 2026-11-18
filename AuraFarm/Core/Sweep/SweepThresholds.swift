import CoreGraphics
import Foundation

/// How a sweep across one sample is paced: how many frames to keep, how far the view has to
/// travel between them, and how much disk one sweep may use.
///
/// PLACEHOLDERS: none of these are calibrated on a real microscope setup. Set them from
/// pilot footage before relying on them.
struct SweepThresholds {
    /// Frames kept per sweep. Twelve 720p JPEGs come to roughly 4 MB.
    var framesPerSweep: Int = 12
    /// How many fields the guide bar draws in a row. A row now ends where the helper says
    /// the cover slip ends, so this is only how wide the bar is drawn, not where the sweep
    /// turns.
    var framesPerRow: Int = 4
    /// How far the view has to have moved from the last kept frame before another is kept, in
    /// pixels, so two frames are not taken of the same field of view. `TravelSinceLastFrame`
    /// measures this against the kept frame itself, so a slide pushed back and forth returns
    /// to where it started and has covered no new ground.
    ///
    /// NOT CALIBRATED on a stage, but measured: on 600 frames of microscope footage this kept
    /// 114 frames with a median of 305 px between them, and every pair could still be lined
    /// up. Raising it was tried earlier at 180, 240 and 300 against a running total of
    /// frame-to-frame shifts, and covered less ground rather than more; that total is no
    /// longer what the threshold is measured against, so those runs say nothing about this
    /// number.
    ///
    /// There is a ceiling either way. Frames are lined up by registration, which needs them to
    /// overlap, and `PanoramaStitcher.maxShiftFraction` refuses a pair that has moved more than
    /// 0.4 of a frame, so on a 1080 px wide frame nothing above 432 can be joined at all.
    var shiftBetweenFrames: Double = 120
    /// How far the view has to have moved before the frame that starts a new row is kept.
    ///
    /// A step down is a whole row, not a nudge along one, and the sweep only measures
    /// distance: without this it keeps the first frame of the new row after the same 120 px
    /// as a sideways nudge, which is a hand's width into the step rather than at the end of
    /// it. The prompt then flips to "move left" while the slide is still on its way down, so
    /// the row that follows lies on top of the one before instead of below it.
    ///
    /// PLACEHOLDER, not calibrated. It has the same ceiling as a sideways step and a tighter
    /// one in practice: `PanoramaStitcher.maxShiftFraction` refuses a pair past 0.4 of a
    /// frame, which is 768 px down a 1920 px tall frame, and the frame above has to still be
    /// joinable to the one below it.
    var shiftBetweenRows: Double = 600
    /// A single reading above this means the slide was moved faster than frames can be placed
    /// against each other. Such a frame is not kept, because the next one could not be lined
    /// up with it; the sweep waits for the slide to be moved at a workable speed.
    var maxStepPixels: Double = 150
    /// Hard ceiling for one sweep, so a single test cannot fill the store.
    var maxBytes: Int = 6 * 1024 * 1024
}
