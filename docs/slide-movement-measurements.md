# Slide movement measurements

How to use **Workbench → Slide movement lab** (debug builds) and what to send back.

The lab tracks where the view is as the slide moves, and logs brightness, sharpness and
contrast for every analysed frame (about 10 per second). It is a measurement tool.
**Nothing in it is calibrated yet.** Every threshold is a placeholder, and these runs are
what will set the numbers. It saves nothing to tests; each log is a CSV you share with
**Export CSV**.

## Before you start

- Clamp the phone over the eyepiece and focus with the Focus slider. Leave it there.
- Open the lab, choose **Live camera**, and check the readout is updating.
- Write down the phone, the microscope, the objective and the slide for every file you send.

## 1. Screen mapping

1. Turn one knob so the view moves clearly one way.
2. In the box over the preview, choose the mapping (and Mirror, if needed) where the dot
   moves the same way on the screen as the view really moves.
3. Write down the mapping, and which knob and turning direction moved the view which way.
4. Repeat for the other knob.

## 2. Drift

1. **Reset position**, then **Start log**, then **Mark start**.
2. Turn one knob until the stage's vernier scale has moved **1.0 mm**. **Mark end** and type `1.0`.
3. Turn back to the start. The position should return near 0.
4. Repeat with **5.0 mm**, and on both axes.
5. Do it once slowly and once at a normal speed.
6. **Stop log**, then **Export CSV**.

## 3. Sample, blank and blurry

With logging on, set the label and hold the view there for about 10 seconds:

- **Sample**: over clearly populated areas.
- **Blank**: over empty glass inside the cover slip.
- **Blurry**: deliberately out of focus.

Do each in 3 different places. Stop the log and export. The table compares the statistics inside
the yellow box, not the whole frame.

## 4. Drop size

Log moving from the left edge of a droplet to the right edge in one pass, then from top to
bottom. Repeat on 2 or 3 slides. Export.

## 5. Stopping

While logging, move, then stop and hold the view still. Do this 10 times. Export.

## 6. Optional: recorded video

Record a video through the microscope with the phone's Camera app: slow knob moves across a
slide. In the lab, choose **Recorded video**, pick it, and **Run**. The same footage can be
measured again later with different settings.

## CSV columns

| Column | Meaning |
|---|---|
| `seconds` | Since the log started (video: since its first analysed frame) |
| `brightness` | Mean luma, 0 to 255 |
| `sharpness` | Variance of the Laplacian of the luma (low = few edges). Blur was seen at about 1 to 2 while moving, about 6 when still |
| `contrast` | Standard deviation of the luma, 0 to 255 |
| `shake_x_px`, `shake_y_px` | Frame-to-frame shift from `ShakeEstimator`, empty when not available |
| `anchor_x_px`, `anchor_y_px` | Live offset of this frame from the anchor frame, empty when the frame became the anchor or registration failed |
| `position_x_px`, `position_y_px` | Odometer position: finished hops plus the live offset |
| `position_x_frames`, `position_y_frames` | The same, divided by the frame's short side |
| `hops` | Re-anchors done (the offset reached 0.3 of the short side) |
| `gaps` | Times tracking was lost and then regained |
| `is_lost` | 1 while tracking is lost (3 readings in a row with no trusted offset) |
| `event` | `hop`, `lost`, `regained`, or empty |
| `hop_agreement` | Correlation of the two frames of a hop, from `PanoramaStitcher.agreement`. Measured at most once a second, otherwise empty. 1 is the same ground, 0 unrelated |
| `label` | `sample`, `blank`, `blurry`, or empty |
| `mark` | `start` or `end`, on the row where Mark was pressed |
| `mark_mm` | Distance typed at `end`, from the vernier scale |
| `frame_width`, `frame_height` | Camera frame size in px |

## Sign convention

Position is where the **view** has travelled across the slide, in the frame's own pixel axes:
x to the right, y down. It is in the same direction as the registered shift
(`ShakeEstimator` and `TravelSinceLastFrame.offset(to:)`, vertical flipped from Vision's
bottom-up). Content on the slide appears to move the opposite way.

One thing to check: a test on synthetic frames reads the registered shift in the SAME
direction as the content's move, not the opposite. If the dot in step 1 goes the opposite
way to the view for every mapping you try, say so: it may be a sign to flip in the odometer.
The mapping you choose in step 1 settles it on real footage.

## Testing by hand (no mechanical stage)

Until the stage arrives the slide is moved by hand, so the screen gives big, glanceable
feedback instead of small numbers.

**Test picker.** Choose the test at the top of the live screen. Its instruction is shown on a
card, and the test is written into every row and into the file name:
`slide-movement-<test>-<yyyyMMdd-HHmmss>.csv` (for example `slide-movement-drift-20261110-143000.csv`).
The tests are Free, 1 · Mapping, 2 · Drift, 3 · Labels, 4 · Drop size and 5 · Stops.

**Setting up.** Opening the lab shows the live camera with a "Set up the phone" card and a
**Start** button. Position the phone over the eyepiece and focus with the slider first; nothing
is analysed until you tap **Start**, which also learns the eyepiece field afresh. **Back to
setup** returns here. Once the field is learned the lab asks "Does this look right?": **Looks
right** starts tracking, **Adjust** lets you drag and resize a circle over the lens and tap
**Done**.

**Reading the screen.**
- **TRACKING** (green): the app is following the slide.
- **TOO FAST** (orange) or **LOST** (red): the slide moved too fast to match from one frame to
  the next. Move slowly and steadily; for LOST, move slowly back to where it last tracked.
- The **speed meter** (bottom left) should stay in the green.
- The **hop ring** around the trail fills as the next hop approaches and flashes on a hop.
- **Off start** is the distance from where you tapped Mark start, in fields; it is green inside
  the home zone (the dashed circle).
- **Still** counts the seconds the view has held still. The stops test wants 2 s or more.
- **1 field = the side of the yellow box**, about the width of the useful view. Hops come at
  about a quarter of a field. The trail has a grid with one line per field, and it zooms out on
  its own when you travel further than 3 fields. The big **Moved** number (or **Off start** once
  you tap Mark start) is the same distance in fields. The readout line "Box 352 px · hop at 88 px"
  shows the box side and the hop distance in use. With Whole frame there is no box, so a field
  is the frame's short side and a hop comes at 30% of it, as before.
- On the trail, a **white dot** is a hop the app tracked, and a **red cross** is where tracking was lost.
- Tap the trail for a full-screen version, with the mapping picker.

**Drift by landmark.** Centre a landmark, tap **Mark start**, go 3–5 fields away, then come back
until the landmark is centred again, and **Mark end** with the distance left empty. The final
**Off start** value is the drift: how far the odometer says you are from where you began.

**Labels.** The table shows contrast and sharpness per label as 10th–50th–90th percentiles. If
the ranges overlap, the app can't tell them apart yet.

**A pessimistic baseline.** Hand-moved numbers are rougher than a mechanical stage will give.
Treat them as a pessimistic baseline and repeat the runs once the stage arrives.

**New CSV columns** (the last seven, after `frame_height`):

| Column | Meaning |
|---|---|
| `test` | The test slug: `free`, `mapping`, `drift`, `labels`, `drop-size`, `stops` |
| `note` | The free text typed in "Notes for this log" |
| `speed_fraction` | Frame-to-frame movement as a share of the box side (the frame's short side with no box), averaged over 3 readings |
| `status` | `starting`, `tracking`, `too_fast` or `lost` |
| `hop_progress` | 0 to 1 towards the next hop |
| `still_seconds` | Seconds the movement has stayed under 2 px per reading |
| `off_start_fields` | Distance from the marked start in fields (box sides); empty with no start marked. Was `off_start_frames` |

The speed, still and "too fast" limits are placeholders and not calibrated. The speed limits were set when the reference was the frame's short side and now mean a share of the box, so re-measure them.

Eight more columns follow, after `off_start_fields`:

| Column | Meaning |
|---|---|
| `field_region` | Where movement was registered: `auto-learned`, `auto-untrusted`, `auto-learning` (still learning), the same three with `bright-region-` for the one-frame mode, `centre-square` or `whole-frame` |
| `analysis_ms` | Time spent analyzing this frame, in milliseconds |
| `analyzed_fps` | Analyzed frames per second over the last second |
| `field_open_share` | The share of the frame learned to be open field (0 to 1); empty when no mask was learned |
| `box_side_px` | The side of the registration box in px (the frame's short side with no box); one field |
| `position_x_fields`, `position_y_fields` | The odometer position divided by `box_side_px` |
| `hop_limit_px` | The hop distance in use, px (a quarter of the box, or 30% of the short side with no box) |

`position_x_frames` and `position_y_frames` stay, in frames of the frame's short side, for
comparison.

Seven more columns close the row, after `hop_limit_px`:

| Column | Meaning |
|---|---|
| `box_brightness`, `box_sharpness`, `box_contrast` | The same three numbers as `brightness`, `sharpness` and `contrast`, measured only inside the yellow box (the whole frame when there is no box). The three earlier columns stay whole-frame, for comparison |
| `reading` | `measured`: the anchor reading agreed with the frame-to-frame movement. `predicted`: it did not, so the last offset plus this frame's shift was used. `missing`: neither was available |
| `predicted_streak` | Readings in a row that were predicted |
| `no_detail` | 1 while the box holds too little detail to follow, else 0 |
| `blind_stretches` | Times the view went over nothing to track |

Thirteen more columns close the row, after `blind_stretches`. The picture and guide columns are
empty when not available:

| Column | Meaning |
|---|---|
| `start_match_x_px`, `start_match_y_px` | Where the Mark start picture sits against this frame, px (held to current). The true change of position since Mark start |
| `true_off_start_fields` | The length of that, in fields |
| `tracker_error_fields` | How far the tracker's change of position since Mark start is from the true one, in fields |
| `blank_returns_matched` | Returns from NO DETAIL recovered by matching the held picture |
| `blank_returns_unmatched` | Returns that could not be matched. The position may be off since then |
| `blank_return` | `matched` or `unmatched` on the frame where it was decided |
| `view_class` | Guide dry run: `sample`, `thin`, `blank`, `blurry` or `dark` |
| `guide_state` | Guide dry run: the route step, for example `column 3 down` |
| `guide_instruction` | Guide dry run: `move`, `holding`, `captured`, `edge_go_back`, `still_no_detail` and so on |
| `guide_target_dx`, `guide_target_dy` | Guide dry run: the vector to the target in fields, screen axes |
| `guide_captures` | Guide dry run: frames it would have captured so far |

The `reading` column can now also say `matching`: detail is back and the picture match is
still deciding. The position stays where it was until then.

`anchor_x_px` and `anchor_y_px` are always what registration returned, even on a `predicted`
row, so a false jump stays visible there; the position uses the predicted value.

## What the lab can and can't track

Tracking now lives in `SlideTracker` and eyepiece field learning in `FieldRegionLearner`, both in
`Core/Imaging`, so the capture screen can use the same code. The lab's `SlideMovementPipeline` is a
thin wrapper around them. Box stats are always sampled at step 4 (`SlideTracker.statsStep`),
because the detail and view thresholds were measured at it; the capture screen's own quality
stats use step 2 and are on a different scale.

- **It can't measure movement over empty glass.** Registration needs detail to lock onto. Over
  blank glass it reads about 0, which looks like "not moving" and silently loses distance. The
  lab now checks the sharpness inside the box; when it stays low the banner says NO DETAIL, the
  distance is paused (it is not counted as lost), the trail is dashed and `no_detail` is 1. Keep
  moves over the sample. When detail returns, the lab matches the last picture with detail (three
  agreeing readings, after three readings to be sure detail is back). If it finds it, the
  position is recovered with no loss (`blank_returns_matched`). If not, it carries on from the
  last known position and counts `blank_returns_unmatched`: the position may be off since then.
  `blind_stretches` counts each time this happened.
- **It rejects readings that disagree with the frame-to-frame movement.** Hand-moved tests
  showed single readings against the anchor jumping to about 250 px while the picture moved a
  few px between frames. A real move cannot do that. Such a reading is replaced by the last
  offset plus the frame-to-frame shift and written as `predicted`. After five predictions in a
  row the prediction is trusted and counted as a hop. Both comparisons crop both frames to the
  yellow box, so the box is matched against the same part of the held frame.
- **The stats are now measured inside the yellow box.** The eyepiece ring dominated the
  whole-frame numbers: blank glass scored the highest contrast. The readout and the label
  statistics table use the box numbers. The detail limit (`minBoxSharpness`, 120) is a
  placeholder set between the blank (about 55) and sample (260 to 600) whole-frame readings;
  re-measure it from `box_sharpness` in labelled logs.
- **Marks.** Mark start and Mark end only work while a log is running (the buttons are greyed
  otherwise). A short "Mark start ✓" or "Mark end ✓" appears on the camera strip, with
  "(not logging)" if nothing was written. The mark lands in the `mark` column of the next row.

## Mechanical stage results (12 November 2026)

Twelve runs (K1, K2, C1–C4, D1–D4, D6, D7) with the X and Y knobs, a 10x objective, a box side
of 344–352 px and about 32 ms of analysis at 10 fps.

| Run | Result |
|---|---|
| 10 of 12 runs | Zero LOST |
| D1, D3, D4 (out and back) | Drift 0.23, 0.34 and 0.17 field |
| C3 | Hop total (587, 107) px against a plain sum of frame-to-frame shifts (588, 103) px |
| D3 | Hops (−115, −11) px against a sum of (−106, −15) px |
| D6 | 1.80 field of error: 39% of the run in NO DETAIL, 5 LOST |
| D7 | 0.96 field: 8% in NO DETAIL |
| D2 | 0.76 field: 9% in NO DETAIL |
| K1 | A full mm lost on the return |

- **Over dense sample, tracking is good.** On clean runs the hop total and the sum of
  frame-to-frame shifts agree almost exactly. Moving readings disagreed with the prediction by a
  median of 0 px and a 90th percentile of 1 px. What is left is close to how well a vernier can
  be read by eye (0.1–0.2 mm), so a measurement that does not depend on the vernier is needed:
  the picture check below.
- **Every large error came from NO DETAIL stretches.** While NO DETAIL shows, the position is
  frozen. Everything that moves meanwhile is lost. Adding up frame-to-frame shifts over those
  stretches does not fix it (it recovered 239 of 262 px on D2, 214 of 524 on K1, and added
  movement on the wrong axis on C4), so the lab matches the held picture instead.
- **Sharpness in the box** (lab scale, every 4th pixel): blank or very sparse 6–100, sparse
  sample 120–280, dense sample 1,000–3,800 (900–2,200 while moving). `minBoxSharpness` = 120
  sits in the right place.
- **Brightness in the box:** blank patches are brighter than sample, about 205–220 against
  165–190 at the same exposure.
- **Scale:** about 530 px per mm on both axes, so one field (the box) is about 0.65 mm. Not
  checked against a landmark (G1 was not run).
- **Not measured:** blurry against blank, stop settling time, repeatability. Their limits are
  guesses.

The conclusion for the guided route: it must never travel across blank glass. Blank is the
edge, so turn back. A short trip over blank must come back to a remembered picture, which the
app matches to recover its exact position.

### Thresholds set from these results

All are PLACEHOLDER and not calibrated.

- `PictureMatchThresholds.maxStepDisagreementOfBox` = 0.05 (about 17 px): readings agreed
  within about 1 px. `readingsToConfirm` = 3 and `maxReadings` = 8 are guesses.
  `maxOffsetOfBox` = 0.4 repeats the hop trust limit.
- `ViewClassifierThresholds.lowDetailBelowSharpness` = 120 and `thinBelowSharpness` = 300: the
  sharpness bands above. `blankBrightnessRatio` = 1.15 and `blankFallbackBrightness` = 195: the
  brightness bands above. `darkBelowBrightness` = 40: nothing that dark was measured.
- `SpotAlignmentThresholds`: `holdSeconds` = 1.0 (settling time not measured),
  `tooFastSpeedFraction` = 0.18 (same as the lab's), and the tolerance and distance limits are
  guesses.
- `GuidedSweepThresholds`: 0.8 field between spots and columns is a 20% overlap. The rest are
  guesses.

### Picture check

Mark start (while logging) stores a small copy of the yellow box. While you stay within 0.4
field of the start, the lab matches that copy against each frame. That gives the true change of
position, with no vernier. The readout under "Off start" shows true distance, the tracker's
distance and the error, all in fields. Mark end adds the true distance to its confirmation. The
check starts again if the box changes (re-detect, field adjusted, region changed) and when you
tap Reset position.

### Guide dry run

Turn on "Guide dry run" in the lab settings. A block shows what the guide would say now, the
route step, the vector to the target (in fields, screen axes), the view class and how many
frames it would have captured. Nothing is saved and no frames are written. The haptic taps on a
capture and when it says to go back from an edge. Pick the screen mapping first: the guide
works in screen axes.

## If the lab shows no movement

**The eyepiece ring.** Through an eyepiece the camera sees a bright round field inside a black
ring that never moves. Registering the whole frame locks onto the ring's edge and reads about
0 px however the slide moves. The lab therefore registers only inside the round field.

**Field region** (a setting under the readout):
- **Auto (learned once)** (default): after Start the lab looks at about 30 frames (around 3
  seconds) and learns which parts of the frame stay dark and touch the frame's edge. That is the
  eyepiece ring. Then it locks that in and measures movement only inside the largest rectangle
  of open field. Move the slide slowly around while it learns, so a dark patch of the slide is
  not mistaken for the ring; nothing is tracked until it is done.
- **Bright region (one frame)**: decides from a single frame: an automatic light/dark cut, the
  largest connected bright region is the field.
- **Centre square**: always a square in the middle of the frame (70% of its height).
- **Whole frame**: the old behaviour, for comparison.

On the camera strip, the **red tint** is the part treated as the eyepiece, and the **yellow
box** is where movement is measured. They are placed by the camera preview layer's own
conversion from frame pixels, which handles the rotation and the crop to fill the screen.

**What the app sees.** Turn on **Show what the app sees** (under the field region) to get a
small picture under the camera strip: the grid the analysis actually uses, in the camera's raw
orientation (not rotated), with the red tint and the yellow box drawn on it. It refreshes about
once a second. Use it to tell a detection problem from a drawing problem:
- If the red and yellow are right on the small picture but wrong on the camera strip, the
  detection is fine and the overlay on the strip is misplaced.
- If they are wrong on the small picture as well, the field was detected wrongly: tap
  **Re-detect field**, use Adjust, or try the other field region.

Tap **Re-detect field** after adjusting the phone or the light. If the readout says "Field: not
found, using centre" (an orange card on the preview), the light may be too dim or the phone too
far off-centre; the centre of the frame is used instead. Dark specks inside the field are not
treated as eyepiece, because they are not joined to the frame's edge.

**Analysis ms and fps.** The readout line "analysis 42 ms · 9.8 fps" is how long each frame took
and how many were analyzed in the last second. It turns **red** above 100 ms or below 5 fps.
Red means the phone is falling behind the camera, so frames get dropped and each step between
two analyzed frames is larger: move more slowly, close other apps and let the phone cool.

"Measure hop agreement" is off by default because it is the dearest step; turn it on only when
you need the `hop_agreement` column. The lab reads sharpness from a coarser sample (every 4th
pixel) than the capture screen (every 2nd), so its sharpness numbers are not on the same scale
as the capture screen's thresholds.

## Soil slide, cover slip edge (E1)

A 22 x 22 mm cover slip filled with soil, guide dry run: left across the edge, about 1 mm past
it, a wait, and back. The tracker did its job; the guide never said "Edge found, go back".

- **Brightness does not tell blank from blur on soil.** Box brightness had a median of 211
  inside the sample and 211 outside, so low detail outside the cover slip read as blurry, not
  blank (`ViewClassifier` calls it blank only at 1.15 times the sample baseline).
- **The edge zone flickers.** NO DETAIL for 0.6 s, detail, NO DETAIL for 1.6 s, then solid for
  12.7 s (box sharpness 79 at the 90th percentile, 125 at most). Inside the sample there was one
  0.3 s flicker.
- **Soil has less detail than the stem the thresholds came from.** Inside sharpness: median
  489, 10th percentile 194.

The rules that follow:

- Low detail of any class (blank, blurry, dark) or tracking paused is the edge.
- It must last `edgeSeconds` = 0.8 s (ignores the 0.3 s interior flicker and the first edge
  flicker, triggers on the 1.6 s one). Detail ends a stretch only after `edgeRecoverySeconds`
  = 0.2 s of it, so one reading of detail between two short stretches does not restart it.
- Refocus never blocks the edge. While travelling to an edge or finding the sample the guide
  says slow down at most. On the way back it says `still_no_detail` once low detail has lasted
  `refocusAfterSeconds` = 6 s.

## Guide dry run: how to read it

With the guide dry run on, the picture is clear of the status banner (the speed meter stays), and
the guide draws on it like the iPhone's Night mode.

- The white cross in the middle is fixed; the thin circle around it is the zone where a target counts as reached. The yellow cross is the next spot, drawn on the picture: turn the knobs until it sits in the circle.
- When the spot is out of view, an arrow pinned inside the edge of the field points to it, with the distance in fields.
- Yellow means move, green on target, orange wrong way or slow down. Hold still and a green ring fills clockwise, then the frame is captured (a white flash, a light tap, the count at the top).
- Over blank glass or with NO DETAIL the position is frozen while the picture still moves, so a cross would sit still on a moving picture. Only an arrow is shown then.
- The line "Axes from preview match: ..." says which manual mapping the preview's own axes are nearest to. It turns orange with "differs from the picker" when that is not the one picked. The guide uses the preview's axes, not the picker's. Sign fix: the tracker's position is the CONTENT's displacement, so the guide negates it to get where the VIEW is; the axes line compares the picker with the preview axes negated (the view-travel map), and `guide_axes_mapping` logs that map's closest mapping.
- The CSV has a new last column, `guide_axes_mapping` (for example `rotateLeft-mirrored`).

## Edge at the centre cross

The whole-box rule missed the cover slip edge when the user stopped as soon as it reached the middle: the centre box still read sharpness 175-212 and dipped under 120 only once, for 0.3 s. The tracker now also measures the sharpness of the four halves of the box (frame axes, same step 4). The route compares the half the view is heading toward (ahead) with the one it is leaving (behind).

- The edge is a candidate when the half ahead is under `halfLowDetailBelowSharpness` (120), the half behind is not, and tracking is on. A candidate must then be confirmed (see "Telling an edge from blur"); only then does the route move on with no trip back, saying "Edge reached" once (a flash and a success tap). It applies to the left edge runs and column legs; steps right and inward probes keep the whole-box rule, since a landing half over the sample is still a valid column.
- The whole-box rule stays as the fallback for overshooting the edge (low detail of any class, or paused, for 0.8 s, then go back).
- New CSV columns, appended last: `box_sharp_left`, `box_sharp_right`, `box_sharp_top`, `box_sharp_bottom`. The 120 cut-off for the halves is a PLACEHOLDER: calibrate it from them.

## Telling an edge from blur

A detail drop alone cannot tell new blank content from the same content out of focus: a flick, a knock or a focus slip fired the edge. An edge must now pass `EdgeConfirmation`.

- **Arrival.** The view must have travelled at least 0.10 field along the heading in the second before the candidate began. A blur leaves the content where it was.
- **Focus comparison.** The tracker compares each half of the box with the same content in the anchor frame (the half's rectangle moved by minus the offset): `halfFocusRatio`, about 1 when unchanged, well below 1 when blurred. The half behind must be at least 0.6 of its sharpness in the last sharp frame. With no arrival, a candidate whose half behind is vouched for this way is still checked, and the ratios of the last tracked reading stand in while the tracker is paused.
- **Confirm while still.** The candidate holds for 1.0 s with the helper still (progress builds only while still; a speed spike of 0.18 or more restarts it). The route says "Checking edge… hold still", then "Edge reached". The whole-box fallback confirms by time alone, after the 0.8 s of low detail.
- **Blur means refocus.** No arrival without vouching, or the half behind (or, in the fallback, both halves of the last tracked reading) under 0.6, is blur: the route says "Refocus" and carries on where it was when detail returns. Blur is never confirmed by a timer: see "Columns edge to edge, and long blur" below.
- **CSV columns**, appended last: `focus_left`, `focus_right`, `focus_top`, `focus_bottom`.
- Every number here (0.10 field, 1 s window, 1.0 s confirm, 0.6 ratios, 0.18 speed) is a PLACEHOLDER to calibrate from the `focus_*` and `box_sharp_*` columns.

## Columns edge to edge, and long blur

On the microscope column 1 turned back after one spot: it started exactly at the left edge, so half the box was over glass for the whole column and a hovering half read as the top edge.

- **Column inset.** When the left edge is found with the edge at the centre cross, column 1 is `columnInsetFields` (0.6) inside it, toward the sample: the first spot is at edge x + 0.6 on the current row. The same for a recheck run. A whole-box overshoot keeps the old rule (the first on-sample position back), and leg ends are not inset.
- **Only an edge ahead ends a leg.** The half ahead must be under 120, the half behind not, and the half ahead at most `halfContrastRatioMax` (0.5) of the half behind (`halves_too_close`). In column legs the two halves across the heading must not clearly differ: the lower is at least `sideBalanceMin` (0.5) of the higher, otherwise the cover slip's side is drifting in (a skewed stage) and the leg carries on (`side_imbalance`).
- **Holding is not resting.** A candidate that began within 0.5 s before the helper reached a spot's target (or after) builds no confirm progress from the hold (`spot_hold`). One that began on the way there is still confirmed.
- **Long blur is decided when detail returns.** After 6 s of whole-box low detail that is blur or undecided the instruction is "still no detail" and nothing is decided. When detail returns: matched within `sameSpotFields` (0.3) of where the stretch began is blur (`same_spot`), and the route carries on exactly where it was. Unmatched, or moved more than that, is an edge reached on the way back (`moved`): the leg or the left edge return completes at the first on-sample position. There is no confirming timer.
- **CSV columns**, appended last: `edge_candidate` (`none`, `half_edge`, `whole_box`), `edge_verdict` (`none`, `checking`, `confirmed`, `blur`), `edge_reason` (empty, or `arrived`, `not_arrived`, `vouched`, `behind_blurred`, `side_imbalance`, `halves_too_close`, `spot_hold`, `speed_spike`, `same_spot`, `moved`, `timeout_no_detail`), then `box_sharp_side_a`, `box_sharp_side_b` (the two halves across the heading that the route used; left and right on an up or down leg).
- Every number here is a PLACEHOLDER to calibrate from those columns.

## Centred field

With **Centre the field** on (the default), once the field is learned and confirmed the preview is cropped to the largest rectangle centred on the field circle (`FieldCentring.cropRect`), scaled to fit and centred in the preview. It trims the red ring area on the side with more room.
It is display only: the box outline, the tint and the guide's marks are drawn in the displayed space, tracking still registers in the learned box in full-frame pixels. Off, or while the field is being learned, reviewed or adjusted, the picture is uncropped.
Phase 3b will crop saved frames with this same rectangle, so what the helper sees is what is kept.

## Lab setup: align, focus, field

Every lab session now starts with a setup, shown as "1 Align · 2 Focus · 3 Field" at the top. While aligning and focusing nothing is learned or tracked, and the phone's own Focus slider is hidden (the lens stays locked; focus with the microscope's Z knob).

- **1 Align.** The bright circle is found with the same automatic cut the mask learner uses. It is drawn green when every check passes and orange otherwise. Checks, worst first: *no circle* (under 5% of the frame is bright); *clipped* (the circle touches a frame edge: a thick red bar along that edge); *not round* (area over the enclosing circle's under 0.85: the phone is off-centre or tilted); *uneven* (darkest of 8 sectors under 0.75 of the brightest: that sector is shaded blue); *glare* (over 1% of the circle saturated, or the brightest sector over 1.25 times the median: shaded red). "Alignment 72 ▲" is a 0 to 100 score (half the worst margin, half the mean margin) with its trend over 2 s. All must pass 1.5 s without a break.
- **2 Focus.** Sharpness (step 4) is measured in a square of 0.7 of the circle's diameter. The best focus is the PEAK over the sweep: the meter shows the current value with a white tick at the highest. Turn one way; "passed the peak" when it falls under 0.7 of it; "almost there" back at 0.9; "focused" after 1 s near the peak and steady. Peaks under 150 for 8 s say "not enough detail, move to sample".
- **3 Field.** The existing learning, review and confirm, then the centred field. "Redo setup" goes back to align; "Re-detect field" goes back to the field step; "Skip align and focus" starts the next session at the field step.
- **Setup log.** "Export setup log" shares the last 2 minutes as `slide-movement-setup-<timestamp>.csv`: `seconds, step, found, circle_x, circle_y, circle_r, clipped_sides, roundness, evenness, darkest_sector, brightest_sector, saturated_share, glare_ratio, score, problems, focus_state, focus_current, focus_peak, focus_level`. Sector 0 points along frame +x and they go clockwise in top-down frame coordinates.
- Every threshold here is a PLACEHOLDER to calibrate from the setup log.

## Stage axes, stage limit and run monitors

- Test 4 (soil): "stage play" was mostly a fixed tilt between camera and stage. Y knob only: 2 mm moved the picture 3.21 and 3.62 fields with 0.50 and 0.54 sideways (about 8.8 degrees); X knob only: 22.3 fields with 4.1 sideways (about 10.4 degrees). Wobble was only ±0.05 field, direction hysteresis about 0.03 field. The stage ran out of Y travel 28 fields (17 mm) below the top edge. The top edge was called blur ("Refocus") for about 12 s, then confirmed in 1.1 s after the helper stepped back and came forward.
- Setup has a 4th step, Stage: the helper turns only the X knob about 2 fields, then only the Y knob (`StageAxesCalibration`). Each run is fitted by total least squares and refused when its perpendicular RMS is over 0.08 field ("Keep to one knob"); axes outside 75 to 105 degrees apart fail and restart. Skip uses the identity.
- The picture and the guide are straightened by the same map (`StageAxes.straightening`, determinant 1, about the field circle's centre), composed with the centring fit in `FramePreviewConverter.displayTransform`. The guide measures its axes through that display, so columns need only the Y knob. The field size and radius are measured from probe-vector lengths, because bounding boxes grow about 1.16 times at 10 degrees. Toggle: "Straighten picture". Phase 3b must apply the same straightening to saved frames.
- The picture is the circle's bounding square (`FieldCentring.cropRect`, margin 1.02), shown full width in a square view with everything outside the circle dark (preview layer `.resizeAspect`, so the whole frame is available to crop). Phase 3b crops saved frames with this same square, then straightens.
- Stage limit: the "Stage limit" button (hint after 6 s on a move) records a y minimum on an up leg, a y maximum on a down leg, an x minimum on the left-edge run and an x maximum on a step right (which finishes with `stageLimit`). Y limits carry to every later column: its last spot is moved onto the limit and the leg ends after its capture, with no tap. The left-edge recheck stops at the x minimum.
- Setup going back: alignment lost after it passed (looser limits, held 2 s) returns to Align and then to where it was; Field and Stage return to Field (mask learned again). The run monitor (`RunMonitor`) pauses the guide when the circle moves (centre 0.12 r or radius 10% for 2 s, geometry only) or the focus index (box Laplacian variance at step 2 over step 6) stays under 0.6 of its baseline for 2.5 s; it resumes within 0.06 r / 5% for 1 s, or at 0.8 of baseline for 1 s. Focus counts only while tracking on sample or thin. The focus baseline is the setup focus step's median over its last 2 s (the 0.7 focus square stands in for the registration box), or the first 3 s after Mark start when setup was skipped. Focus is judged only with the guide dry run on.
- Check-edge rule: a low-detail stretch that began while moving normally (not still, no speed spike) on the left-edge run or a column leg and judged blur says "Step back a little, then come forward again" at once; the whole-box arrival then decides. Still or flick onsets keep "Refocus". After the 6 s refocus wait it is "still no detail" as before.
- Every new threshold is a PLACEHOLDER. Calibrate from the setup log (`stage_*` columns) and the movement CSV (`monitor_state`, `focus_index`, `focus_baseline`, `circle_shift_r`, `circle_radius_change`, event `stage_limit`, instruction `check_edge`).
- Phase 2i, from reviewing against Test 4: the check-edge rule judges motion from the readings WITH detail in the 0.5 s before the stretch (latest not still, none at a flick speed), because on blank frames the speed is noise (the top edge read 0.28 to 1.05 with the position frozen, after detail readings at 0.034). No detail reading in that window means Refocus.
- The focus monitor counts only still readings: moving smears the picture (box sharpness while moving at speed 0.1 to 0.2 was a median 0.56, 10th percentile 0.33, of the nearest still reading), and Test 4 moved about 17 fields in 30 s. A pause needs 2.5 s of still low readings, a resume 1 s of still good ones; the fallback baseline uses still readings only.
- A spot is not captured while the monitor's latest still reading is under 0.6 of the baseline (`focus_low` column); the hold restarts in full when it clears, and the 2.5 s pause takes over if it stays low.

- Phase 2j, stage step in sparse areas (setup run of 16 Nov 2026, soil): on the Y knob `stage_travel_fields` sat at 0.30 from 42 s to 80 s, then went 0.33 to 2.01 in 80-87 s. Measured from the recording, box detail (Laplacian variance, relative units) was about 200-400 during the X step, 17-150 on the stuck Y stretch, and 51-55 s was empty glass (about 17). The tracker rightly froze the position; the screen said nothing. Now the step says "Start on a patch with plenty of particles", and 1.0 s without tracking in a row shows "Nothing to follow here. Turn back, or move to a patch with more particles" with the bar dimmed. The setup log gained `tracking`, `position_x_fields`, `position_y_fields`, `box_sharpness`, `view_class`, `still_seconds` (field and stage steps).
- Still-onset focus rule: an edge can only be reached by moving, so box detail that drops while the slide was still and stays low is focus (or a bump). A low-detail stretch (tracking paused, or view class blank or blurry; not dark) pauses for focus after 2.5 s when the detail readings in the 0.5 s before it were still and its median box sharpness is at most 0.5 of theirs (`focus_still_onset` column). A stretch that began while moving, or with nothing before it, stays the route's job. Resume as before (still detail readings at 0.8 of baseline for 1 s; without a baseline, detail plus still for 1 s).
- Edge-line detector (`EdgeLineDetector`, LOGGED AND DRAWN ONLY; no guide decision uses it): finds a line across the whole box where brightness steps along the heading's normal, straight or irregular (angles within 12 degrees, 8 parts, up to 2 bins of wander between parts). A candidate has coverage 0.75 or more and strength 6 or more (both PLACEHOLDER). Calibrate from the movement CSV's `edge_line_strength`, `edge_line_coverage` and `edge_line_slide_residual` (about 0 means the line moves with the slide, about the slide's movement means dust on the optics) on the next test; `edge_line_candidate`, `_angle_deg`, `_offset_fields` and `_sign` come with them. Phase 2k would confirm a candidate by asking the helper to slide along it.
- Phase 2k, corner edge (failed_edge_detection.csv, 16 Nov 2026, soil, column 1 up, rotateLeft): the edge was the cover slip's top-left corner. At 13.5-15.0 s, still, the halves along the heading were 60 (ahead) and 660 (behind) but the halves across were `box_sharp_side_a` 600 and `side_b` 90, so `side_imbalance` (0.5) rejected it for good. Column 1 sits 0.6 field inside the left edge and the box half-width is 0.5, so the left edge is inside the side half all along the column. Now, when the low side half faces a known edge x (the left edge column 1 was set inside, or a recorded stage x limit) within `sideEdgeReachFields` = 1.1 of the column, the half-box edge is accepted with reason `corner`; a low side facing the sample still says `side_imbalance`. `GuideReading.sideADirection` carries where side A's picture lies on screen; without it nothing changes.
- Sparse tracking: the tracker froze whenever box sharpness was under 120, but a few distinct particles average to a low variance while coarse structure stays (16 Nov stage step; only a few seconds were truly empty glass, about 17). A frame now also counts as detail when box sharpness is 30 or more, at least 4 of the 6 x 6 cells hold 2 or more pixels with |Laplacian| of 40 or more (step 2), and at least 2 of the 4 quarters hold a cell (all PLACEHOLDER, `DetailThresholds`; same debounce; lab toggle "Track sparse sample"). Consistency, prediction and hop checks are unchanged. Columns: movement CSV `feature_cells`, `feature_quarters`, `sparse_tracking`; setup log `feature_cells`. The route, ViewClassifier and edge rules are unchanged: a sparse frame still reads as low detail for edges by its view class; only the position keeps updating.
- Focus dial (`FocusDial`): sharpness alone cannot say which side of focus the knob is on, but a drop of 10% from a local maximum within 85% of the target says it passed the peak. Setup shows the old one-sided meter until the peak has been passed once, then a two-sided dial (target = the peak, raised by a new peak). The run's focus pause shows the dial from its first reading against the baseline (side unknown until the value rises, or falls 10%: "Wrong way. Turn the other way"). Green zone half-width is 1 minus the share that counts as sharp (0.9 near in setup, 0.8 resume in the run). Columns: movement CSV `focus_dial_offset` (-1 not far enough, +1 too far) and `focus_dial_side`; setup log the same.
- Edge-line fixes (still logged only): the plain-sample run read coverage 1.0, strength about 6, offset always -0.415 and residual 0.000 for 8 s, which is the eyepiece's illumination ramp, and the real corner read at the angle limit with coverage 0.25. The gradient is now taken on luma minus a box blur of 1/6 of the box; a part counts only if its bin also stands 2x above the median of the bins 3 to 6 away; the angle range is 30 degrees (3 degree steps); `longestRun` (contiguous covered parts of 8) was added, and a candidate is (coverage 0.75 or run of 5) and strength 6 (PLACEHOLDER). New column `edge_line_longest_run`.
- Frame snapshots (lab only): the full luma frame as an 8-bit grayscale PNG named with the movement CSV's seconds (`frame-013.53.png`), saved when `edge_reason` becomes side_imbalance, corner, halves_too_close or vouched, the edge line turns on, the instruction becomes check_edge or an edge is confirmed (at most 1 a second, 80 a session), or with the "Save frame" button. The CSV `snapshot` column names the file on its row and "Export CSV" offers the frames with the CSV. A 1280 x 720 PNG of busy synthetic texture is about 0.7 MB; real soil frames should be about the same or smaller.
- Phase 2m, stage step: the Phase 2l knob-direction check was removed. Rejection and failure messages ("Keep to one knob", "Axes don't look right") stay 2.0 s and the bar stays at 0 meanwhile; readings during them are not counted. When X is accepted, "X done ✓ Stop turning" shows for 0.5 s with the bar full and no reading counts, so X movement left over does not join the Y run, which starts from the first tracked position after the pause. Redoing the field forgets the old straightening (`stageAxes` is nil until the new calibration is done), so the new stage step measures unstraightened.
- Phase 2l, corner needs quarter evidence: Phase 2k accepted any side imbalance whose low side faced a known edge within 1.1 field, and column 1 is always within that reach, so any sparse patch ahead (ahead half under 120, behind 120 or more) was a "corner": the top edge was confirmed about 13 to 14 fields early. The real 15 Nov corner took the box from about 1050 to 350 and only the behind quarter away from the edge kept sample. A corner now also needs aheadAway under 120, behindAway at least 120 (quarters in heading terms, relative to the low side half) and the box at most 0.5 of its median over the detail readings of the last 3.0 s before the candidate began; otherwise the reason is `corner_rejected` (`side_imbalance` stays for a low side facing away from every known edge). Columns: `quad_ahead_away`, `quad_ahead_toward`, `quad_behind_away`, `quad_behind_toward`, `corner_box_share`; `corner_rejected` also triggers a frame snapshot. Calibrate the 0.5 and 3.0 from those columns on the next soil run.
- Phase 2m, lost moves (slide-movement-free-20261116-134233.csv, free mode, soil): from 5.9 to 13.0 s the X knob was turned with detail present (box sharpness about 530), the frame-to-frame shifts (`shake_y_px`) added up to 468 px, and the tracked position moved 30 px. The anchor reading (`anchor_y_px`) stayed at 0 +- 12 px, even in still frames after the move. `ReadingConsistency` only compared the anchor reading with the last accepted offset plus this frame's shift (gate 0.12 x box side, 39 px at box 322), so a match stuck on something static was never far off in one frame, was accepted every frame, and reset the prediction each time. In the later stretches (23.2 to 29.0 s, sharpness 900 to 1500) the anchor worked and the sum of shifts matched the position within 1 px (538 against 539 px in y).
- The chain rule: `ReadingConsistency` keeps the plain sum of the frame-to-frame shifts since the anchor (not pulled toward the anchor reading, so a stuck anchor cannot drag it back). An anchor reading is measured only if it passes the old per-frame gate AND is within 6 px + 10% of the chain's length of the chain (PLACEHOLDER; where the anchor worked, chain and anchor agreed within 2 px); otherwise the verdict is predicted, with the chain as the prediction, and 5 predicted in a row still commit as a hop. A frame with no frame shift breaks the chain until the next reset, which falls back to the old rule. Replayed on the CSV rows, the 5.9 to 13.0 s window now keeps 468 px of the 468 (the old rule kept 30), and the 23.2 to 29.0 s window gives 540 px in y against the CSV's 539, with 50 of 59 readings measured. Columns: `chain_x_px`, `chain_y_px`, `anchor_chain_gap_px`.
- Phase 2n, ghost frames (slide-movement-free-20261116-142046.csv, free mode, soil, phone and slide still): about every 1.5 s one frame reported a frame-to-frame shift of about +242 px in x (the anchor reading too), and the next -242 px, with identical brightness and contrast; speed jumped to 0.25 to 0.75, status went too_fast, the guide looped "Slow down" / "Follow the arrow", and at 8.6 to 10 s it caused a lost/regained and about 13 px of false position. x in the frame is the screen Y axis (rotateLeft), which is why Y tracking looked worse. Offline, `VNTranslationalImageRegistrationRequest` on a 322 px box at (722, 415) of the snapshots reproduced it: every pair with frame-003.47 read +-242 px in x although nothing moved; shifts of 10 px in x read -242, 60 px in x read 125 px of false y, 60 px in y read -14 px of false x. A strong static brightness gradient (a vignette band and a shadow patch on the left) dominates the correlation and makes an alias peak along x.
- The fix: both box crops are high-passed before Vision sees them, `clamp((luma - gaussian(luma, 12 px)) x 4 + 0.5, 0, 1)` (`RegistrationFilter`, vImage separable Gaussian, radius 3 sigma; PLACEHOLDER `blurSigmaPx` 12, `gain` 4, `mid` 0.5). Offline all 30 still pairs read within 2 px and every synthetic shift (+-10 to 60 px, x, y and diagonal) within 2 px with no cross-axis error. The stored picture is still the raw crop and is filtered when it is registered. The filtered crops of the current frame, the previous frame and the anchor are cached by buffer identity, so a frame filters once. The whole-frame paths with no box (`TravelSinceLastFrame`, `ShakeEstimator`) are unchanged: the lab always runs with a box once the field is known.
- The safety net: a frame whose frame-to-frame shift exceeds 0.4 of the box side (129 px on 322; the fastest real move logged was about 33 px a frame, the ghosts 231 to 242) is dropped: no frame shift and no anchor reading is used, the chain and odometer do not change, the previous frame stays the last good one, the reading column says `ghost`, and the frame carries the last good shake so speed and still seconds carry on. Three ghosts in a row are taken as real and fall back to the missing-shift rule. Columns: `ghost_frames` (running count), `ghost_fallbacks`.
- Phase 2o, edges are confirmed only when still: `GuideReading.isStill` was `stillSeconds > 0`, so one still frame counted; `EdgeConfirmation`'s half-edge time never reset when the helper moved, and the whole-box rule confirmed after `confirmSeconds` with no stillness at all. Now both candidates add to the held time only while still and set it back to 0 on any reading that is not (reason `moving`, verdict checking 0, so the candidate can still be shown), and confirm only when the candidate has held AND `GuideReading.stillSeconds` is at least `confirmSeconds` (1.0). Paths changed: half-edge and whole-box confirmation in `EdgeConfirmation` (so the left-edge run, a column leg's `edgeReached`, `takeWholeBoxEdge` and the re-approach after check-edge all go through it) and `SlideRoute.decideLongBlur`, whose "moved" decision after a long blur now waits until the helper has been still for `confirmSeconds`.
- Full-cover-slip mode (lab toggle "Full cover slip (line edges)", `slideLab.fullCoverSlip`, default on; `GuidedSweepThresholds.fullCoverSlip`, off in the library): the sample fills the cover slip, so the edge is the cover slip's line, straight or irregular, not a patch of low detail. `EdgeLine` results (angle limit now 45 degrees in 4.5 degree steps; the 16 Nov corner band ran at 45 to 50) go to the route in `GuideReading.edgeLine`. `LineEdgeTracker` (PLACEHOLDER `LineEdgeThresholds`): a candidate line within 45 degrees of perpendicular to the heading and ahead is `ahead`; at least 3 of the last 5 moving readings with a candidate whose |slide residual| is at most 0.15 field make it `attached` (proven ON THE SLIDE: the lighting falloff and shadow patch stay fixed on screen); `confirmed` needs attached, |offset| at most 0.25 field (at the cross), the line still present (a gap under 0.5 s does not reset), and the slide still for 1.0 s in a row (moving resets the timer). A line never seen to move with the slide is never confirmed: at the cross it gives check-edge. Half edges, blank boxes, side imbalance, corner and corner_rejected are still computed and logged but decide nothing; a blank box after moving gives check-edge ("Step back until the edge line is in view"). New instruction `line_ahead` ("Edge line ahead. Keep going until it reaches the centre cross"). Columns `line_state`, `line_attached_count`, `edge_mode`; snapshots on `line_attached` and `line_confirmed`; the overlay draws the path cyan, green once attached, and "edge" at confirmation.
- CAVEAT: the line thresholds are uncalibrated. `EdgeLineDetector` has only been logged so far; it locked onto the lighting falloff in 2j and missed a diagonal band in 2k, and the residual rule can still pass a line fixed to the optics when the slide moves very slowly (a fixed line's residual equals the movement between two detector runs, which is under 0.15 field at slow speeds). Calibrate from `edge_line_strength`, `edge_line_coverage`, `edge_line_slide_residual`, `line_state`, `line_attached_count` and the snapshots on the next full-cover-slip run, and switch the toggle off to get the previous rules back exactly.
- The full-cover-slip route is the same zig-zag (left edge, column 1 at the inset, up then down passing captured spots, step right by 0.8, a short leg toward the near edge and then the full leg, spots every 0.8, stage limits) with no left-edge recheck (`maxLeftRechecks` treated as 0) and no inward probing: on a step right a confirmed line edge, or landing on a blank box at rest, finishes the route with the new `SweepFinishReason.rightEdge` (raw value `rightEdge`; old manifests still decode, since only a case was added).
- Phase 2p, the 16 Nov 2026 15:32 full-cover run (slide-movement-free-20261116-153212.csv, soil, 44 snapshots): the left edge is a clear dark line, nearly horizontal in the frame, with sample on one side and almost empty glass on the other. `EdgeLineDetector` read it at strength 44 to 53, coverage 1.0, angle 0 (15.5 to 17 s), and every other candidate in the run at 6.06 to 7.03. The line confirmed the left edge at 17.10 s; then the inset trip to column 1 (heading screen-right, via the dry run's last heading) made the probe look right, the same line at the cross went ahead, attached and confirmed again at 24.5 s and ended column 1's up leg after about 0.25 field; on the down leg the column's own side line read -36 to -40.5 degrees (the 45 degree limit) as a candidate at strength 26 to 42. From about 36 s on a sparse stretch (sharpness about 90, blurry, focus index rising so not defocus) frames with 0 to 11 feature cells and sharpness 15 to 60 were still registered and "measured" 38 to 53 px a frame, so the position jumped, while frames with 22 to 34 cells tracked normally.
- Fixes: a frame with detail on but fewer than 12 feature cells is skipped like a ghost (reading `sparse_skip`, no shift or anchor reading, previous frame kept, chain and odometer unchanged; 5 in a row go to the no-detail pause; column `sparse_skips`). The route's `edgeHeading` (screen left on the left-edge run, the leg's direction on a column leg once the view is on the column, screen right on a step right; nil on returns, the inset trip, edge spots, holds, travel) is the only direction the lab's edge probe looks along; with nil no line is evaluated and the tracker resets. A candidate needs strength 20 (was 6), and a result within one angle step of the 45 degree limit (40.5 or more) is a line outside the range searched, not a candidate.
- Known and rejected edges: a confirmed edge (by the rule or the helper) is remembered in guide coordinates (heading normal, line angle, position along the normal). A later candidate within 15 degrees and 0.5 field of a known edge is ignored when it looks back at it (the opposite heading); the same heading is not ignored, because the zig-zag meets the same top and bottom line on every column and each leg must end on it. A rejected line is ignored from either side for the rest of the leg or run. Beyond-side rule: `EdgeLineDetector` measures the texture energy (mean |gradient|^2 of the picture with its slow illumination taken away, both axes) in a band behind and a band beyond the path, each from 0.06 to 0.36 field from it, and the tracker accepts the line only if beyond is at most 0.5 of before (the empty side of a real edge read about 6 against about 500 in the box halves; about 0.05 in these bands). Confirmation now needs 2.0 s (was 1.0) at rest, in a row, for the line and the legacy rules, and in line mode the blank-box and half-edge rules say nothing: no check-edge, no checking, "Nothing to follow here" for a blank box, `edge_verdict` written as "off".
- Feedback buttons (lab; "Ask me to confirm edges", `slideLab.askEdges`, default on): when a line is attached and within 0.25 field of the cross ("Stay still, edge detected") the overlay shows "✓ Edge" and "✗ Not an edge"; with the toggle on the rule never confirms by itself, with it off it confirms after 2.0 s still. "Mark edge here" is shown whenever an edge is looked for and confirms an edge at the cross along `edgeHeading`. Taps are CSV events `edge_user_yes`, `edge_user_no` and `edge_user_mark` with a snapshot each (they bypass the 1 a second limit but count toward the 80); `edge_feedback` is yes, no, mark or auto. Calibrate from `edge_line_strength`, `edge_line_coverage`, `edge_line_slide_residual`, `line_before_energy`, `line_beyond_energy`, `line_state`, `line_attached_count`, `edge_feedback` and the snapshots. On the 5 real fixtures (400 px crops of 017.10, 020.26, 024.50, 005.77 and a no-edge frame) the cover-slip edge frames read strength 37.6 to 43.8, angle 4.5, beyond/before about 0.05 along the empty side and are not candidates along a leg; the weak dense and sparse boundary reads 9.4.

### 16 Nov 2026 22:04 (dark lighting, line mode) and Phase 2q
- 191 of 1819 frames were `sparse_skip`, but 75% had box sharpness >= 150 (median 370): FeatureCells reads low on this lighting. The skips gave 121 no_detail rows and about 690 px (2.2 fields) of uncounted movement on column 1. A frame is now skipped only with feature cells < 12 AND box sharpness < `maxSharpnessForSparseSkip` (150; the 15:32 junk read 15-60).
- The marked left edge (41-46 s) read strength 8.8-12.1, coverage 0.75-0.875, beyond 1.5-1.9 against before 40-47 (about 0.04); sample-area lines read <= 4.4 here and 6.06-7.03 in the 15:32 bright field (real edges 26-53). Two-factor rule: `candidateStrength` 20 -> 8 AND beyond <= `beyondShareMax` 0.25 x before; neither alone is enough, whatever the tracker state.
- The top edge (175-194 s) had no line readings: `edgeHeading` was nil while the view was off the column x or holding. It is now set for the whole column leg (and the left-edge run and the step right) whatever the instruction; nil only on returns, the inset trip to the column start (until the view first reaches the column), edge spots and recheck travel.
- With the tracked position frozen (no_detail, paused, matching, a skip) "moves with the slide" is proven from the sum of the frame shifts since the last line reading, projected on the normal; attached when the residual is <= 0.15 field. CSV `line_attach_source` is tracker, chain or empty.
- Marked-frame fixtures (`edge-dark-051-46`, `edge-dark-194-61`, 400 px crops) are in `EdgeLineFixtureTests`; the dark thresholds are not tuned to them yet.

### 16 Nov 2026 22:56 (bright, line mode) and Phase 2r
- Left (18 s) and bottom (286 s) edges were confirmed by the line rule: strength 11.7-33.9, beyond about 1 against before 30-70. After the bottom edge the step right started column 2 going DOWN, 0.8 field below the edge. In full-cover mode a step right now starts the column away from the edge the last one ended on, as ONE leg (legsDone starts at 1): column 1 up then down, column 2 up, column 3 down; the previous edge is a known edge for it. Legacy mode is unchanged.
- Top edge (column 1 up, 105-133 s): the wavy band read strength 9.3-10.8, coverage 1.0, beyond 1.1-1.6 against before 20-37, but at -40.5 to -45 degrees (dropped at the 45 limit); 106.9-110.6 s candidates at -18 to -36 degrees sat at offset -0.23 to -0.38, behind the cross, on clear glass (sharpness 30-60); 123-125 s strength 18-23 at -0.31. The guide said "refocus". The search is now 60 degrees (27 angles; the at-limit rule still rejects side edges at about 90).
- A passing line between -0.8 field (`maxBehindFields`) and the cross is "behind": instruction `edge_behind` ("Edge just behind you. Come back until it's on the cross", arrow back along the leg), state `behind` in `line_state`, snapshot reason `edge_behind`. Coming back with matching movement it becomes ahead, attached and at the cross as before. While a line was seen within 2.0 s (`lineMemorySeconds`) "refocus" and "nothing to follow" are replaced by the line's own words.
