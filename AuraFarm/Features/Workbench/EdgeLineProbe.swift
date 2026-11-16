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

        func update(_ path: [CGPoint]) {
            if self.path != path { self.path = path }
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
        private var step = EdgeLineProbe.fineStep

        func reset() {
            counter = 0
            previous = nil
            previousPosition = nil
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
            var change: Double?
            if let previousPosition {
                let moved = CGPoint(
                    x: tracked.positionFields.x - previousPosition.x,
                    y: tracked.positionFields.y - previousPosition.y)
                change = (Double(moved.x * direction.x) + Double(moved.y * direction.y)) / length
            }
            let line = EdgeLineDetector.detect(
                grid: grid, box: box, normal: direction, previous: previous,
                trackedChangeFields: change)
            previous = line
            previousPosition = tracked.positionFields
            return line
        }
    }
#endif
