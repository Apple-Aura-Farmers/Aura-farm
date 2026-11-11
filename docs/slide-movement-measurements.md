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

Do each in 3 different places. Stop the log and export.

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

**Reading the screen.**
- **TRACKING** (green): the app is following the slide.
- **TOO FAST** (orange) or **LOST** (red): the slide moved too fast to match from one frame to
  the next. Move slowly and steadily; for LOST, move slowly back to where it last tracked.
- The **speed meter** (bottom left) should stay in the green.
- The **hop ring** around the trail fills as the next hop approaches and flashes on a hop.
- **Off start** is the distance from where you tapped Mark start, in frames; it is green inside
  the home zone (the dashed circle).
- **Still** counts the seconds the view has held still. The stops test wants 2 s or more.
- **1 frame = the height of the camera view** (the short side). The trail has a grid with one line per frame, and it zooms out on its own when you travel further than 3 frames. The big **Moved** number (or **Off start** once you tap Mark start) is the same distance in frames.
- On the trail, a **white dot** is a hop the app tracked, and a **red cross** is where tracking was lost.
- Tap the trail for a full-screen version, with the mapping picker.

**Drift by landmark.** Centre a landmark, tap **Mark start**, go 3–5 frames away, then come back
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
| `speed_fraction` | Frame-to-frame movement as a share of the frame's short side, averaged over 3 readings |
| `status` | `starting`, `tracking`, `too_fast` or `lost` |
| `hop_progress` | 0 to 1 towards the next hop |
| `still_seconds` | Seconds the movement has stayed under 2 px per reading |
| `off_start_frames` | Distance from the marked start in frames; empty with no start marked |

The speed, still and "too fast" limits are placeholders and not calibrated.

Four more columns follow, after `off_start_frames`:

| Column | Meaning |
|---|---|
| `field_region` | Where movement was registered: `auto-learned`, `auto-untrusted`, `auto-learning` (still learning), `centre-square` or `whole-frame` |
| `analysis_ms` | Time spent analyzing this frame, in milliseconds |
| `analyzed_fps` | Analyzed frames per second over the last second |
| `field_open_share` | The share of the frame learned to be open field (0 to 1); empty when no mask was learned |

## If the lab shows no movement

**The eyepiece ring.** Through an eyepiece the camera sees a bright round field inside a black
ring that never moves. Registering the whole frame locks onto the ring's edge and reads about
0 px however the slide moves. The lab therefore registers only inside the round field.

**Field region** (a setting under the readout):
- **Auto (learned once)** (default): at the start of a session the lab looks at about 15
  frames (around 1.5 seconds) and learns which parts of the frame stay dark and touch the
  frame's edge. That is the eyepiece ring. Then it locks that in and measures movement only
  inside the largest rectangle of open field. Hold steady or move the slide gently while it
  learns; nothing is tracked until it is done.
- **Centre square**: always a square in the middle of the frame (70% of its height).
- **Whole frame**: the old behaviour, for comparison.

On the camera strip, the **red tint** is the part treated as the eyepiece, and the **yellow
box** is where movement is measured. They are drawn through the screen mapping, so they are
only as well aligned as that mapping is; a rough match is expected.

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
