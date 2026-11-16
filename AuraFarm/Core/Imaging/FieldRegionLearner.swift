import CoreGraphics
import CoreVideo
import Foundation

/// What `FieldRegionLearner.process` made of one frame.
struct FieldRegionUpdate: Equatable {
    /// This frame went to learning the mask, or to waiting for review, so it must not be
    /// tracked.
    var spentLearning: Bool
    /// The box differs from the last frame's, or learning finished, or the field was
    /// confirmed, adjusted or re-detected. The tracker must reset before the next tracked
    /// frame.
    var regionChanged: Bool
}

/// Works out where on the camera frame movement is measured: the whole frame, a centre
/// square, or the open field of the eyepiece, learned from the camera's own frames.
///
/// One instance per run; every call must come from the same serial queue. It keeps small
/// copies of each frame's luma while learning, never the buffers themselves.
final class FieldRegionLearner {
    /// Where registration looks. Choosing a mode that learns the mask starts learning.
    var mode = FieldRegionMode.auto {
        didSet { if mode != oldValue, mode.learnsMask { restart() } }
    }

    /// Where the mask has got to.
    private(set) var state = FieldState.learning(progress: 0)

    /// When true, tracking waits after the mask is learned until `confirm()`, so the person
    /// can check it (and adjust it with `adjust(to:)`) first.
    var requiresReview = false
    private(set) var isAwaitingReview = false
    /// Where registration looks once the mode and the mask are settled, in frame pixels; nil
    /// for the whole frame and while learning.
    private(set) var registrationRect: CGRect?

    private let maskThresholds: FieldMaskThresholds
    private var builder: FieldMaskBuilder?
    private var lastFrameSize = CGSize.zero
    /// The rect of the last processed frame, to tell when the box moved.
    private var lastRect: CGRect?
    private var hasProcessedFrame = false
    /// Set by anything that changes the region outside `process`; reported by the next one.
    private var pendingChange = false

    init(maskThresholds: FieldMaskThresholds = FieldMaskThresholds()) {
        self.maskThresholds = maskThresholds
    }

    /// Whether the eyepiece mask is still being learned.
    var isLearning: Bool {
        if case .learning = state { return true }
        return false
    }

    /// Feeds one frame: learns from it if the mask is still being learned, then works out the
    /// region the mode and the mask call for.
    func process(_ buffer: CVPixelBuffer, frameSize: CGSize) -> FieldRegionUpdate {
        lastFrameSize = frameSize
        let spent = mode.learnsMask && (learn(from: buffer, frameSize: frameSize) || isAwaitingReview)
        applyRegion(frameSize: frameSize)
        let moved = hasProcessedFrame && registrationRect != lastRect
        hasProcessedFrame = true
        lastRect = registrationRect
        let changed = pendingChange || moved
        pendingChange = false
        return FieldRegionUpdate(spentLearning: spent, regionChanged: changed)
    }

    /// The person is happy with the field: tracking starts afresh from the next frame.
    func confirm() {
        guard isAwaitingReview else { return }
        isAwaitingReview = false
        pendingChange = true
    }

    /// Replaces the learned field with a circle the person drew.
    func adjust(to circle: FieldCircle) {
        guard mode.learnsMask, lastFrameSize != .zero else { return }
        let mask = circle.clamped(to: lastFrameSize).mask(
            frameSize: lastFrameSize, thresholds: maskThresholds)
        state = mask.isTrusted ? .ready(mask) : .untrusted(mask)
        pendingChange = true
    }

    /// Forgets the learned mask and learns it again.
    func redetect() {
        restart()
    }

    /// Starts learning again, but only a mask that is still being learned; one already
    /// learned is kept.
    func restartIfLearning() {
        if mode.learnsMask, isLearning { restart() }
    }

    private func restart() {
        builder = nil
        isAwaitingReview = false
        state = .learning(progress: 0)
        registrationRect = nil
        pendingChange = true
    }

    /// Auto learns over several frames with a slightly lowered cut; the bright-region mode
    /// decides from one frame at the plain automatic cut.
    private var learningThresholds: FieldMaskThresholds {
        guard mode == .brightRegion else { return maskThresholds }
        var single = maskThresholds
        single.framesToLearn = 1
        single.cutScale = 1
        return single
    }

    /// Feeds the frame to the mask builder while learning. Returns whether this frame was
    /// spent learning (so it is not tracked).
    private func learn(from buffer: CVPixelBuffer, frameSize: CGSize) -> Bool {
        guard case .learning = state else { return false }
        var builder =
            self.builder
            ?? FieldMaskBuilder(
                width: Int(frameSize.width), height: Int(frameSize.height),
                thresholds: learningThresholds)
        if let grid = LumaGrid.sample(of: buffer, step: maskThresholds.gridStep) {
            builder.add(luma: grid.luma, gridWidth: grid.width, gridHeight: grid.height)
        }
        self.builder = builder
        if builder.isComplete, let mask = builder.result() {
            self.builder = nil
            // Tracking starts afresh from the next frame, inside the settled region.
            pendingChange = true
            state = mask.isTrusted ? .ready(mask) : .untrusted(mask)
            isAwaitingReview = requiresReview
        } else {
            state = .learning(progress: builder.progress)
        }
        return true
    }

    /// Works out the region the mode and the mask call for.
    private func applyRegion(frameSize: CGSize) {
        switch mode {
        case .wholeFrame:
            registrationRect = nil
        case .centreSquare:
            registrationRect = EyepieceField.centreSquare(frameSize: frameSize)
        case .auto, .brightRegion:
            switch state {
            case .learning: registrationRect = nil
            case .ready(let mask): registrationRect = mask.registrationRect
            case .untrusted: registrationRect = EyepieceField.centreSquare(frameSize: frameSize)
            }
        }
    }
}
