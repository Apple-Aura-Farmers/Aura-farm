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
- **Automatic sweep** — the helper moves the sample to the left and the app keeps
  frames on its own as the view travels, twelve of them across the slide. Nobody is
  asked to stop or hold still. Saving pauses only while the image is too dark or out of
  focus, and starts again by itself once that is fixed. Shake does not pause it: a sweep
  is the slide moving, and a slide moved too fast reads as blurred anyway.
- **Frame extraction instead of video** — a sweep is saved as a folder of JPEG frames
  in `Documents/FrameSets`, with a `manifest.json` holding the sample ID, field number,
  moisture, grams of soil, millilitres scanned and the frame count. Frames are never
  overwritten or edited.
- **One joined image** — when the sweep ends, the frames are lined up into a single
  wide picture of the slide, the way a panorama works. The slide travels on a flat
  stage, so frame to frame there is a shift and nothing else, which makes translational
  registration the whole job. The panorama is a derived file saved as `panorama.jpg`
  beside the frames; the frames themselves are never edited to make it, and a sweep
  whose frames cannot be lined up keeps every one of them.
- **Size ceiling** — a sweep stops at its own limit, and the saved-sweeps screen shows
  how much of the 50 MB store is used.
- **Sweep library** — saved sweeps newest first. Open one and it shows the joined
  image, scrolled along the slide, or switch to the frames, which play back like a
  clip, a second a frame, or step through one at a time. The frames are drawn in
  grayscale, so the files on disk keep their colour.
- **Export** — frames can be copied off the phone with the Files app.

### Why frames, not video

The store holds 50 MB in total. A sweep of a dozen stills covers several fields of view
for a few MB, where a clip of the same sweep would not fit. The counting work needs
separate fields of view rather than continuous footage, so the frames are the raw data
now and the same rule applies to them: nothing in the app edits or deletes one.

**Planned**

- Sample preparation and microscope mounting guides
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

The thresholds (brightness 60, sharpness 100, shake 3 px) are uncalibrated starting
guesses. Calibrate them against a real microscope before trusting them: record good
and bad examples, read the live numbers from the debug readout, and set the thresholds
between them.

Known limitations:

- A field with little in it has little texture, so the sharpness score can read low
  even when focus is right. Expect false "out of focus" warnings on empty fields.
- There is no autofocus, because it hunts on a microscope where the image only changes
  when the stage moves. Focus is locked and set by hand.
- Shake is measured on the whole frame. A large moving organism barely affects it, but
  a drifting slide or debris flow could.
- Brightness does not detect over-exposure.
- Joining the frames needs something to lock onto. On a field with little in it, the
  registration can return a confident but badly wrong match, and a frame pasted far out
  of place makes the whole picture misleading. A shift of more than half a frame is
  therefore treated as a failure to line up: the sweep keeps its frames and says they
  were not joined, rather than showing a panorama that cannot be trusted.
- Nothing checks free space before a sweep. A full phone fails part-way through, and
  the frames written so far are kept.
- The app knows the slide moved, not which way it moved. It asks for a move to the left
  and counts how far the view has travelled, so moving the wrong way still lets the
  sweep go on and can cover the same part of the sample twice.

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

Engineering rules and code conventions are in [CONTRIBUTING.md](CONTRIBUTING.md).
