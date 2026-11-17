#if DEBUG
    import CoreGraphics
    import Observation

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
            /// "none", "out_of_range", "matching" or "confirmed"; see `SlideMovementStep`.
            var pictureCheck = "none"
            var trueOffStartFields: Double?
            var trackerErrorFields: Double?

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
            /// The guide's captured spots and its current target, in the same space as `trail`.
            var guideCaptured: [CGPoint] = []
            var guideTarget: CGPoint?
            /// The predicted top, bottom and right edges as segments in the same space as `trail`.
            var predicted: [PredictedTrailLine] = []
        }

        /// The guide dry run's block. Counters drive haptics, like `Readouts`.
        struct Guide: Equatable {
            var isOn = false
            var instruction = ""
            var state = ""
            /// The vector to the target, in fields (screen axes); nil when there is none.
            var targetDx: Double?
            var targetDy: Double?
            var viewClass = ""
            var captures = 0
            var captureCount = 0
            var edgeCount = 0
            var isFinished = false
            /// Entries into too far / other way, for the haptic warning.
            var wrongWayCount = 0
            /// Edges found with the edge at the centre of the view, for the success haptic.
            var edgeReachedCount = 0
            /// "Axes from preview match: Rotate 90° left"; empty without preview axes.
            var axesLine = ""
            /// True when the preview's axes are nearest to a different mapping than the picker's.
            var axesDiffer = false
            /// The instruction has been to move, travel or follow the arrow for a while: the
            /// stage may have run out (offers the Stage limit button).
            var showsStageLimitHint = false
            /// Times the Stage limit button was used, for the haptic.
            var stageLimitCount = 0
            /// "End after this column" was chosen and the run waits for the column to finish.
            var pendingEnd = false
            /// A column is being swept: "End after this column" is offered.
            var columnInProgress = false
            var spotMode = SpotConfirmMode.briefTouch
        }

        /// The speed bar and the status banner, which the helper steers by: full rate.
        @Observable
        final class SpeedState {
            var speedFraction = 0.0
            var status = MovementIndicators.Status.starting
        }

        /// What the haptics watch. Published at full rate, only when one of them changes, so a tap
        /// is never held back by the throttled panels.
        struct Haptics: Equatable {
            var hops = 0
            var lost = 0
            var captures = 0
            var edges = 0
            var wrongWays = 0
            var edgesReached = 0
            var stageLimits = 0
            var organisms = 0
            var monitor = RunMonitorState.ok
            var stopReached = false
        }

        /// What End run depends on, at full rate: the run is ending after this column, a column is
        /// being swept, the run is finished.
        struct RunControl: Equatable {
            var pendingEnd = false
            var columnInProgress = false
            var isFinished = false
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
