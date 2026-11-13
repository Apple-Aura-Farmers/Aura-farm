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
| `guide_instruction` | Guide dry run: `move`, `holding`, `captured`, `edge_go_back` and so on |
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
