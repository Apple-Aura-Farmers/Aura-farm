#if DEBUG
    import CoreGraphics

    /// What the lab publishes to its screen, in separate pieces so each small view reads only
    /// what it shows and a change to the text readouts does not redraw the trail.
    enum SlideMovementInfo {
        /// For the status banner and the speed meter.
        struct Status: Equatable {
            var status = MovementIndicators.Status.starting
            var speedFraction = 0.0
        }

        /// For the text readouts and the big numbers.
        struct Readouts: Equatable {
            var stats: FrameStats?
            var position = CGPoint.zero
            var positionFrames = CGPoint.zero
            var positionFields = CGPoint.zero
            /// The registration box's side and the hop distance, px.
            var boxSide = 0.0
            var hopLimit = 0.0
            var hops = 0
            var gaps = 0
            var lastEvent = ""
            var frameSize = CGSize.zero
            var stillSeconds = 0.0
            var offStartFields: Double?
            var isHome = false
            var elapsedLogSeconds = 0.0
            /// Counters the screen watches to drive haptics, so the model needs no UIKit.
            var hopCount = 0
            var lostCount = 0
            var analysisMilliseconds = 0.0
            var analyzedFps = 0.0
            /// Statistics inside the registration box; `stats` is the whole frame's.
            var boxStats: FrameStats?
            /// "measured", "predicted" or "missing".
            var reading = ""
            var hasDetail = true
            var blindStretches = 0

            /// How far the view is from the marked start, or from where the position was last
            /// reset when no start is marked, in fields.
            var distanceFields: Double {
                offStartFields ?? hypot(Double(positionFields.x), Double(positionFields.y))
            }
        }

        /// For the trail drawing. Positions are in fields.
        struct Trail: Equatable {
            var trail: [CGPoint] = []
            /// Where hops were tracked and where tracking was lost, so the trail shows what the
            /// app actually followed.
            var hopPoints: [CGPoint] = []
            var lostPoints: [CGPoint] = []
            /// Where Mark start was pressed, in the same space as `trail`.
            var startPoint: CGPoint?
            var hopProgress = 0.0
            var hopCount = 0
            /// Parallel to `trail`: true where the box held nothing to follow, drawn dashed.
            var blind: [Bool] = []
        }

        /// For the cards and outlines drawn on the camera preview, in frame pixels.
        struct Field: Equatable {
            var state: FieldState?
            var registrationRect: CGRect?
            var frameSize = CGSize.zero
            /// True while the learned field waits for the person to confirm or adjust it.
            var awaitingReview = false
            /// The learned field as a circle, to start adjusting from; set while awaiting review.
            var circle: FieldCircle?
        }
    }
#endif
