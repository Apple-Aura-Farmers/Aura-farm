#if DEBUG
    import CoreGraphics
    import CoreVideo
    import Foundation
    import Observation

    /// The edge line's cyan path, published for the overlay. Main queue only.
    @Observable
    final class EdgeLineState {
        /// The candidate's path in frame pixels; empty when there is none.
        private(set) var path: [CGPoint] = []

        /// How far the guide's line rule has got: "", "none", "ahead", "attached" or "confirmed".
        private(set) var lineState = ""

        func update(_ path: [CGPoint]) {
            if self.path != path { self.path = path }
        }

        func setLineState(_ state: String) {
            if lineState != state { lineState = state }
        }
    }

    /// Runs `EdgeLineDetector` on every 2nd analyzed frame of the guided dry run and keeps what
    /// it needs between runs. LOGGED AND DRAWN ONLY. Analysis queue only.
    final class EdgeLineProbe {
        /// Run on every Nth analyzed frame. PLACEHOLDER: 5 a second is plenty to log and draw.
        static let everyNthFrame = 2
        /// Cell size in frame pixels; 3 when a call takes longer than `slowMilliseconds`.
        static let fineStep = 2
        static let coarseStep = 3
        /// The budget per call, milliseconds.
        static let slowMilliseconds = 3.0

        /// How long the last call took, in milliseconds.
        private(set) var milliseconds = 0.0

        private var counter = 0
        private var previous: EdgeLine?
        private var previousPosition: CGPoint?
        private var previousLive = false
        /// The frame-to-frame shifts (px) since the last line reading: the chain that proves
        /// "moves with the slide" while the tracked position is frozen.
        private var chainShift = CGPoint.zero
        private var chainFrames = 0
        private var step = EdgeLineProbe.fineStep

        func reset() {
            counter = 0
            previous = nil
            previousPosition = nil
            previousLive = false
            chainShift = .zero
            chainFrames = 0
        }

        /// The result on a frame it ran on, else nil. `direction` is the heading's frame vector.
        func update(
            _ buffer: CVPixelBuffer, step tracked: SlideMovementStep, direction: CGPoint?
        ) -> EdgeLine? {
            counter += 1
            guard let direction, let box = tracked.registrationRect else {
                reset()
                return nil
            }
            if let shake = tracked.shake {
                chainShift = CGPoint(x: chainShift.x + shake.x, y: chainShift.y + shake.y)
                chainFrames += 1
            }
            guard counter % Self.everyNthFrame == 0 else { return nil }
            let started = ContinuousClock.now
            defer {
                let taken = ContinuousClock.now - started
                milliseconds =
                    Double(taken.components.seconds) * 1000
                    + Double(taken.components.attoseconds) / 1e15
                step = milliseconds > Self.slowMilliseconds ? Self.coarseStep : Self.fineStep
            }
            guard let grid = EdgeLineGrid.sample(of: buffer, in: box, step: step) else { return nil }
            let length = max(hypot(Double(direction.x), Double(direction.y)), 1e-9)
            // The tracked position while it is live (now and at the last reading); else the chain
            // of frame shifts, which still moves when the position is frozen (no detail, paused,
            // matching, a skip). No shift in the window: neither, and no residual.
            let live = tracked.tracking.trackingState == .tracking && previousLive
            var change: Double?
            var source = ""
            if live, let previousPosition {
                let moved = CGPoint(
                    x: tracked.positionFields.x - previousPosition.x,
                    y: tracked.positionFields.y - previousPosition.y)
                change = (Double(moved.x * direction.x) + Double(moved.y * direction.y)) / length
                source = "tracker"
            } else if chainFrames > 0, tracked.boxSide > 0 {
                change =
                    (Double(chainShift.x * direction.x) + Double(chainShift.y * direction.y))
                    / length / tracked.boxSide
                source = "chain"
            }
            var line = EdgeLineDetector.detect(
                grid: grid, box: box, normal: direction, previous: previous,
                trackedChangeFields: change)
            if line?.slideResidualFields != nil { line?.attachSource = source }
            previous = line
            previousPosition = tracked.positionFields
            previousLive = tracked.tracking.trackingState == .tracking
            chainShift = .zero
            chainFrames = 0
            return line
        }
    }
#endif
