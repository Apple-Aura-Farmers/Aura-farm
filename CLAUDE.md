# CLAUDE.md

Guidance for Claude Code when working in this repository. The product itself is
described in [README.md](README.md); this file is the engineering contract.

## What this app is

Aura Farm is an AI-driven microscopy iOS app. A field helper attaches an iPhone to a
microscope (~100x), prepares a rice paddy soil sample with an in-app guide, records
the sample, and the app detects the microbes that indicate soil health, shows a
result, and recommends actions the farmer can take.

The product goal is to cut the time from sampling to action from weeks to the same
visit. The primary user is a field helper, not a scientist.

**Current scope: the capture quality check and raw recording.** There is no computer
vision, no result and no recommendation code. Do not add ML, counting, scoring or
recommendation code until a labelled dataset and a pilot exist
([AF-15](https://linear.app/aurafarmers/issue/AF-15/collect-initial-labeled-soil-microscope-image-dataset),
[AF-19](https://linear.app/aurafarmers/issue/AF-19/spike-computer-vision-feasibility-for-our-first-soil-indicator)).

## Product rules that constrain the code

These come from the PRD and apply to anything built later. They are not optional:

- **Every result ships with recommended actions.** A results screen without actions
  is not finished.
- **Always return something.** A partial result with its confidence stated beats no
  result. Say plainly when a retest or a lab test is needed.
- **Recommendations must be doable** by a farmer with no technical knowledge.
- **State the limits.** The app says what it cannot detect, compared with a lab test.
- One test is one record: input, result and recommendation together, so History and
  PDF export have something whole to show.

## Where this fits in the pipeline

```
1 Capture → 2 CHECK → 3 Save raw (both built) → 4 Stabilize → 5 Fix lighting
→ 6 Grayscale → 7 Find movers → 8 Find shapes → 9 Merge → 10 Track → 11 Pick + crop
→ model → result → recommendation
```

Step 2 warns the user before recording if the live image is too dark, blurry or
shaky. Step 3 saves the clip and its metadata to `Documents/RawClips`; the Record
button is only enabled once the check passes. Steps 4 onwards are not started.

In PRD terms, the repository covers the capture and quality-check part of Flow 2.
Onboarding (Flow 1), analysis, results, recommendations, History and PDF export
(Flow 3) do not exist yet.

## Tech stack

- Swift 5 language mode, SwiftUI, iOS 17+, iPhone only, portrait only
- AVFoundation (camera), Vision (shake estimate), CoreVideo (pixel access)
- Plain Xcode project (`MicroscopeCounter/MicroscopeCounter.xcodeproj`), committed to
  git. Info.plist values are build settings (`INFOPLIST_KEY_*`), so there is no
  Info.plist file.
- XCTest for unit tests
- No third-party dependencies. Ask before adding one.

## Commands

```
open MicroscopeCounter/MicroscopeCounter.xcodeproj
```

Before running on a device, set your Team under Signing & Capabilities for both
targets and change the placeholder bundle ID `com.example.microscopecounter`.

Run tests: `xcodebuild test -scheme MicroscopeCounter -destination 'platform=iOS Simulator,name=iPhone 17'`

The simulator name has to match a runtime installed on the machine;
`xcrun simctl list devices available` shows them.

The camera does not work in the Simulator. Test the check screen on a real iPhone,
with the phone on the microscope.

New Swift files must be added to the Xcode project: create them from Xcode
(File > New > File) inside the matching group, with the right target ticked. Keep the
folders on disk matching the Xcode groups. Do not hand-edit `project.pbxproj` unless
there is no other way.

`.github/workflows/swift-ci.yml` runs the same build and tests on `macos-15` for
every pull request into `main`, picking whichever iPhone simulator the runner has.

## Structure

```
MicroscopeCounter/
  Sources/
    App/        App entry point
    Capture/    Camera session, frame analysis, quality monitor
    Views/      SwiftUI screens
  Tests/        Unit tests
  MicroscopeCounter.xcodeproj
```

Key files:
- `Views/SampleSetupView.swift`: the first screen. Sample details, and the way into the saved clips.
- `Capture/ClipLibrary.swift`: lists saved clips with their sidecar details. Read only.
- `Views/RecordedClipsView.swift`: the saved clips, newest first, with playback.
- `Capture/ClipRecorder.swift`: the movie output, clip naming, and the metadata sidecar.
- `Capture/RecordingMetadata.swift`: what a clip is of, and the rules for a usable file name.
- `Views/SampleDetailsView.swift`: the form itself, used by the setup screen and by the options menu.
- `Capture/CaptureQualityMonitor.swift`: pure logic. Thresholds, readings, and the raise/clear hysteresis. Foundation only, so it is easy to unit test.
- `Capture/FrameAnalyzer.swift`: brightness and sharpness from the luma plane, plus the shake estimator (Vision).
- `Capture/CameraQualityModel.swift`: owns the AVCaptureSession, feeds frames to the analyzer, publishes state to the UI.
- `Views/CaptureCheckView.swift`: preview, status banner, gated Record button, options menu. Tap the banner to show live numbers.

## How the check works

| Issue | Measure | Method |
|---|---|---|
| Too dark | Mean brightness, 0 to 255 | Average of the luma plane |
| Blurry | Sharpness | Variance of the Laplacian on the luma plane |
| Shaky | Shift in pixels between analyzed frames | Vision translational registration, averaged over the last few frames |

- Frames are analyzed at roughly 10 fps (every 3rd frame at 30 fps).
- An issue is raised after several bad readings in a row and cleared after several good ones, so the banner does not flicker. Counts are in `CaptureQualityThresholds`.
- Only one issue is shown at a time, in the order dark, blurry, shaky. Blur is not evaluated while the image is too dark, because a dark image always reads as blurry.
- Record stays disabled until the check has settled and no issue is active.

This is the PRD's "alerts for unclear images, naming the human step to take". Keep
the copy telling the helper what to do, not what was measured.

### Thresholds are placeholders

The numbers in `CaptureQualityThresholds` (brightness 60, sharpness 100, shake 3 px)
are starting guesses. They have not been calibrated on a real microscope setup.
Calibrate them in the pilot with real footage: record good and bad examples, read the
live numbers from the debug readout, and set thresholds between them. Do not present
them as validated.

### Known limitations

- A field with very little in it (clear fluid, few particles) has little texture, so the sharpness score can be low even when focus is right. Expect false "out of focus" warnings on empty fields.
- There is no autofocus: it hunts on a microscope, where the image only changes when the stage moves. Focus is locked and set by hand with the focus slider.
- Shake is measured on the whole frame. Large moving organisms barely affect it, but a drifting slide or debris flow could.
- Brightness does not detect over-exposure. Add that if testing shows it matters.
- Nothing checks free space before recording. A full phone fails part-way through a clip, and that part-clip is kept.

## Screen flow

1. **Sample details** (`SampleSetupView`): asked for before the camera opens, because every clip needs them. Start is disabled until sample ID, grams of soil and millilitres scanned are filled in. The amount fields start empty, never at 0, so an untyped amount cannot be mistaken for a measured one: they are `Double?` in `RecordingMetadata`.
2. **Check and record** (`CaptureCheckView`): preview, quality banner, focus slider, Record. The details can still be edited from the options menu.
3. When a clip is saved the screen goes back to the sample details, with the field number already counted up, ready for the next field.
4. **Recorded clips** (`RecordedClipsView`): reached from the first screen. Newest first, with sample details, size and playback. Read only, like everything that touches raw footage.

Playback starts in grayscale, because that is what the counting pipeline works on.
The grayscale is applied while playing, with a `CIPhotoEffectMono` video composition
on the player item; the file on disk stays in colour. The toolbar toggle switches back
to colour to check the clip as recorded.

This flow is a developer-facing stand-in for the PRD's Scan flow. The sample
preparation guide, the mounting check and the "move the sample" prompt are not built.

## How recording works

The Record button is enabled once the check has settled with no issue, and stays
enabled while recording so the clip can always be stopped. Recording does not stop on
its own if the image goes bad; the banner says what is wrong and the helper decides.

- Clips go to `Documents/RawClips`, named `<sample>_f<field>_<yyyyMMdd-HHmmss>.mov`, with the time in UTC so clips from different phones sort together.
- If that name is taken, `-2`, `-3` and so on are appended. An existing clip is never overwritten.
- Each clip gets a sidecar `<same base>.json` holding sample ID, field number, flooded or drained, grams of soil, millilitres scanned, and the recording time (ISO 8601).
- Sample details are kept between clips. The field number goes up by one after each saved clip; everything else carries over until it is edited.
- A clip with no readable sidecar is still listed in Recorded clips, under its file name.
- A clip that stops early is kept, not deleted, and the banner says to check it before using it. Raw footage is never thrown away by the app.
- There is no audio input, so clips are silent. The movie connection is rotated 90 degrees, so clips are portrait like the preview.
- `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` are on, so clips can be copied off the phone with the Files app.

## Camera options

The focus slider sits above the Record button. Focus is always locked
(`setFocusModeLocked(lensPosition:)`), never automatic; the slider moves the lens from
0 (closest) to 1 (furthest) and it stays where it is put.

`CameraQualityModel.defaultLensPosition` is where the lens starts. It is a PLACEHOLDER
of 1.0, not calibrated for any microscope and lens: find the value that focuses your
setup with the slider, then set it there.

The menu in the top right of the check screen:

- **Grayscale preview**: preview only. Clips always record in colour. Grayscale is pipeline step 6 and runs on copies, never on raw footage. Playback in Recorded clips is grayscale for the same reason, also without touching the file.
- **Show numbers**: the live brightness, sharpness and shake readout, for calibrating thresholds.
- **Sample details**: the same form as the first screen, for when the sample changes without leaving the camera.

## Rules for this project

1. **Never overwrite or edit raw video.** Raw footage is the source for training data. Processing steps work on copies.
2. **Keep analysis off the main thread.** Frames arrive on a background queue; only publish UI state on the main queue.
3. **Do not hold on to camera buffers.** Keep at most one previous frame for shake estimation.
4. **Keep detection logic out of views.** Views read state from the model; thresholds and rules live in `Capture/`.
5. **Thresholds are data, not magic numbers.** Put new ones in `CaptureQualityThresholds` with a comment saying whether they are calibrated.
6. **Do not claim accuracy.** The PRD's 80% agreement with expert or lab identification is a target to confirm, not a finding. No accuracy numbers in code, UI or docs until measured against expert counts, with train and test split by video or sample (never by frame).
7. **Calibration matters.** Counts need real sizes. When the counting stage is built, pixel-to-µm calibration (stage micrometer clip) is required per phone and lens setup.
8. **No soil verdict without the actions behind it.** Do not ship a rating, score or band on its own; the PRD requires recommendations with every result.

## UI copy

The users are field helpers, not scientists. Use short, plain sentences that say what
to do ("Add more light under the slide"), not what the algorithm measured. Do not say
"healthy" or "no life in soil" anywhere; this app does not judge soil, and an empty
slide usually means a sampling problem. A result the helper has to explain to a farmer
has to be sayable out loud.

## Roadmap (not started)

1. Onboarding, sample preparation guide and mounting check (PRD Flow 1)
2. Calibration clip and pixels-to-µm scale
3. Stabilize, lighting fix, motion and shape candidate finding, tracking, crop
4. Manual tally mode (also generates labelled training data)
5. Model integration after a dataset exists and a pilot sets the thresholds
6. Result, recommendations, History and PDF export (PRD Flow 3)

Done: the capture quality check, and recording raw clips with a metadata sidecar
behind the gated button. The thresholds it gates on are still uncalibrated.
