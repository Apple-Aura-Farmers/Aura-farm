# Aura Farm

An iOS app that turns an iPhone and a microscope into an on-site soil test.

A field helper mounts the phone on a microscope, prepares a soil sample with the
in-app guide, records the sample, and the app looks for the microbes that indicate
soil health. The helper gets a result and recommended actions during the visit, and
can explain both to the farmer on the spot.

## Why

A lab soil test takes two weeks or more and costs money. In that time a farmer cannot
see whether their soil is getting worse, and when the results finally arrive they
often do not say what to do next. Aura Farm aims to shorten that from weeks to
minutes, and to always answer the farmer's real question: what should I do about it.

Built for rice paddy soil at about 100x magnification. The primary user is a field
helper visiting farms, not a lab technician.

## Features

**Built today**

- **Capture quality check** — reads the live image and warns when it is too dark,
  blurry or shaky, in plain language that says what to fix. Record stays disabled
  until the image is usable.
- **Manual focus** — a focus slider instead of autofocus, which hunts on a microscope.
- **Raw clip recording** — saves silent portrait `.mov` clips to `Documents/RawClips`,
  with a JSON sidecar holding the sample ID, field number, moisture, grams of soil and
  millilitres scanned. Clips are never overwritten or edited.
- **Clip library** — saved clips newest first, with their sample details and playback.
  Playback is grayscale, applied live, so the file on disk keeps its colour.
- **Export** — clips can be copied off the phone with the Files app.

**Planned**

- Sample preparation and microscope mounting guides
- Guided recording with a prompt to move the sample across the slide
- Microbe detection with computer vision
- A soil health result the helper can read out, with its confidence
- Recommended actions with every result
- History of past tests, and PDF export of a single record

Nothing in the detection, result or recommendation list is started. The app does not
score soil yet, and it does not claim any accuracy.

## How the quality check works

| Problem | Measure | Method |
|---|---|---|
| Too dark | Mean brightness, 0 to 255 | Average of the luma plane |
| Blurry | Sharpness | Variance of the Laplacian on the luma plane |
| Shaky | Shift in pixels between frames | Vision translational registration |

Frames are analysed at roughly 10 fps on a background queue. A warning appears after
several bad readings in a row and clears after several good ones, so the banner does
not flicker, and only one problem shows at a time.

The thresholds are uncalibrated starting guesses. Calibrate them against a real
microscope before trusting them: record good and bad examples, read the live numbers
from the debug readout, and set the thresholds between them.

## Getting started

```bash
open MicroscopeCounter/MicroscopeCounter.xcodeproj
```

Set your Team under Signing & Capabilities for both targets and replace the
placeholder bundle ID `com.example.microscopecounter`.

Requires iOS 17 or later, iPhone, portrait only. No third-party dependencies.

Run the unit tests:

```bash
xcodebuild test -scheme MicroscopeCounter -destination 'platform=iOS Simulator,name=iPhone 17'
```

The simulator name has to match a runtime installed on your machine;
`xcrun simctl list devices available` lists them.

The camera does not work in the Simulator. Test the capture screen on a real iPhone,
mounted on the microscope.

## Repository layout

```
MicroscopeCounter/
  Sources/
    App/        App entry point
    Capture/    Camera session, frame analysis, quality monitor, recording
    Views/      SwiftUI screens
  Tests/        Unit tests
```

## Contributing

`main` is the trunk and is never pushed to directly. Branch off it with a `feat/`,
`fix/` or `chore/` prefix, open a pull request, and squash merge once the checks pass.
[CONTRIBUTING.md](CONTRIBUTING.md) has the branch strategy, the merge rules and what
must not be committed.

Every pull request into `main` runs:

| Check | Does |
|---|---|
| `Build and test` | Builds the app and runs the unit tests on an iOS Simulator |
| `Format check` | `swift-format lint`, settings in `.swift-format` |
| `Repo checks` | Every Swift file is in the Xcode project; no video or file over 5 MB |
| `Conflict check` | Labels the pull request `has-conflicts` when it stops merging cleanly |

Engineering rules, thresholds and known limitations are in [CLAUDE.md](CLAUDE.md).
