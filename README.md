# Aura Farm

An iOS app that turns an iPhone and a microscope into an on-site soil test, and a Mac
app that keeps the results by farm and field.

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
- **Automatic sweep along a set path** — the app walks the helper across the slide in
  rows: four frames to the right, one step down, four back to the left, down again, and
  so on, twelve frames in all, with a dot for each frame in the row and a bar for the
  sweep so there is nothing to count. Frames save on their own as the view travels;
  nobody is asked to stop or hold still. Saving pauses only while the image is too dark or out of
  focus, and starts again by itself once that is fixed. Shake does not pause it: a sweep
  is the slide moving, and a slide moved too fast reads as blurred anyway.
- **Frame extraction instead of video** — a sweep is saved as a folder of JPEG frames
  in `Documents/FrameSets`, with a `manifest.json` holding the sample ID, field number,
  moisture, grams of soil, millilitres scanned and the frame count. Frames are never
  overwritten or edited.
- **One joined image** — when the sweep ends, the frames are lined up into a single
  picture of the slide, the way a panorama works. The slide travels on a flat stage, so
  frame to frame there is a shift and nothing else, which makes translational
  registration the whole job. The picture takes its shape from wherever the sample
  actually went, worked out from the frames themselves rather than from the path the app
  asked for, so it is rarely a neat rectangle: slide the sweep never covered is left
  black. Pinch to zoom in on it, or double-tap. The panorama is a derived file saved as
  `panorama.jpg` beside the frames; the frames themselves are never edited to make it,
  and a sweep whose frames cannot be lined up keeps every one of them.
- **Size ceiling** — a sweep stops at its own limit, and the saved-sweeps screen shows
  how much of the 50 MB store is used.
- **Sweep library** — saved sweeps newest first. Open one and it shows the joined
  image, scrolled and zoomed around the slide, or switch to the frames, which play back
  like a clip, a second a frame, or step through one at a time. The frames are drawn in
  grayscale, so the files on disk keep their colour.
- **Live counting** — during a sweep a Core ML detector outlines five groups of soil
  organisms and counts each one once as the slide moves. The count is saved with the
  sweep. It is not calibrated and claims no accuracy.
- **Send to Mac** — a saved sweep with counts shares a `.aurafarm` soil report by
  AirDrop, Files or Mail, for the farm manager.
- **Export** — frames can be copied off the phone with the Files app.

**Farm manager (Mac)**

- **Farms and fields** — each farm with its farmer, village and notes, and the fields
  (paddies) it is split into.
- **Inbox** — soil reports from the iPhone land here. Open a `.aurafarm` file, drag it
  onto the window, or use File › Import Soil Reports. The same sweep sent twice is
  recognised and skipped.
- **Soil tests** — file each test under its field, then see what was counted, as a chart
  and a table, with the sample details, how it was counted, the slide and notes.
- **Trends** — organisms counted per field over time, on each farm's page.

The Mac app shows raw counts only. It gives no soil rating, because a rating needs the
recommended actions behind it, and those are not built yet.

### Why frames, not video

The store holds 50 MB in total. A sweep of a dozen stills covers several fields of view
for a few MB, where a clip of the same sweep would not fit. The counting work needs
separate fields of view rather than continuous footage, so the frames are the raw data
now and the same rule applies to them: nothing in the app edits or deletes one.

**Planned**

- Sample preparation and microscope mounting guides
- Calibrated counts (pixel to µm per phone and lens) measured against expert counts
- A soil health result the helper can read out, with its confidence
- Recommended actions with every result
- History of past tests, and PDF export of a single record

Nothing in the result or recommendation list is started. Neither app scores soil yet,
and neither claims any accuracy.

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
- A frame is kept once the view has moved far enough from where the last one was taken,
  and only while the slide is moving slowly enough for the next frame to be lined up
  against it. Moving it in a hurry does not lose ground — the travel still counts — but
  no frame is kept until it slows down.
- Nothing checks free space before a sweep. A full phone fails part-way through, and
  the frames written so far are kept.
- The app asks for a direction but cannot tell which way the slide actually went: the
  travel that spaces frames apart is a distance, not a direction. Going the wrong way
  still lets the sweep run and can cover the same ground twice. It does show up in the
  joined picture, which is built from where the frames really landed.
- Frames are lined up against the one before them, so error builds along the path. Two
  rows that sit next to each other are never checked against each other, and a long
  sweep can drift.

## Trying stitching without a microscope

Debug builds have a **Stitch from video** screen on the first screen, behind the
hammer. It reads a recording frame by frame through the same analyzer, quality check,
sweep rules and writer the camera uses, and saves an ordinary sweep, so the result
opens in Saved sweeps like any other. Put `.mov` or `.mp4` files in the app's
`Documents/DebugVideos` folder — on a simulator:

```bash
xcrun simctl get_app_container booted io.github.apple-aura-farmers.aurafarm data
```

then copy them into `Documents/DebugVideos` inside what it prints. On a phone the app's
folder is already visible in the Files app.

Pick a start time by hand: most of a recording is not a steady pass across a slide, and
a part that is not will come back as frames that could not be joined.

## Getting started

```bash
cp Config/Local.example.xcconfig Config/Local.xcconfig   # then put your team ID in it
open AuraFarm.xcodeproj
```

Signing lives in `Config/Local.xcconfig`, which is gitignored, so set your team there
rather than under Signing & Capabilities (that writes it into the shared project file).
Bundle identifiers start with `AURA_BUNDLE_ID_PREFIX` from `Config/Base.xcconfig`; override
it in your `Local.xcconfig` if it is already registered to another team.

Requires Xcode 16 or later. The field app runs on iOS 17 or later, iPhone, portrait only;
the farm manager on macOS 14 or later. No third-party dependencies.

| Scheme | Builds |
|---|---|
| `AuraFarm` | The iOS field app and its tests |
| `AuraFarmManager` | The Mac farm manager and its tests |

Run the unit tests:

```bash
xcodebuild test -scheme AuraFarm -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test -scheme AuraFarmManager -destination 'platform=macOS'
swift test --package-path AuraFarmKit
```

The simulator name has to match a runtime installed on your machine;
`xcrun simctl list devices available` lists them.

The camera does not work in the Simulator. Test the capture screen on a real iPhone,
mounted on the microscope.

To try the hand-off end to end: on the iPhone, open a sweep in Saved sweeps, tap Send to
Mac and AirDrop it to your Mac, then open the file there. Run the farm manager once first
so the Mac knows it opens `.aurafarm` files.

## Repository layout

```
AuraFarm.xcodeproj      The Xcode project. Target folders are synchronized: a file
                        added to one on disk is in that target, no project edit needed.
AuraFarm/               iOS field app
  App/                  App entry point
  Core/
    Imaging/            Frame analysis, quality check, panorama stitching
    Sweep/              Sweep rules, recorder, saved-sweep library, sample details
    Detection/          Core ML organism detector, tally, benchmark
  Features/             SwiftUI screens, one folder per feature
    SampleSetup/  Capture/  SweepLibrary/  Workbench/
  Resources/            Core ML model
AuraFarmTests/          Unit tests for the iOS app
AuraFarmManager/        macOS farm manager
  App/                  App entry point, file opening, menu commands
  Models/               SwiftData records: Farm, Field, SoilTest, OrganismCount
  Services/             Importing soil reports
  Features/             SwiftUI screens: Navigation/  Farms/  SoilTests/
AuraFarmManagerTests/   Unit tests for the Mac app
AuraFarmKit/            Swift package both apps share: the .aurafarm soil report format
Config/                 Shared xcconfig, Info.plist additions, your gitignored Local.xcconfig
```

## Contributing

`main` is the trunk and is never pushed to directly. Branch off it with a `feat/`,
`fix/` or `chore/` prefix, open a pull request, and squash merge once the checks pass.
[CONTRIBUTING.md](CONTRIBUTING.md) has the branch strategy, the merge rules and what
must not be committed.

Every pull request into `main` runs:

| Check | Does |
|---|---|
| `Build and test` | Builds the iOS app and runs its unit tests on an iOS Simulator |
| `Mac build and test` | Builds the Mac app and runs its unit tests |
| `AuraFarmKit tests` | Runs the shared package's unit tests |
| `Format check` | `swift-format lint`, settings in `.swift-format` |
| `Repo checks` | Every Swift file is inside a target folder; no video or file over 5 MB |
| `Conflict check` | Labels the pull request `has-conflicts` when it stops merging cleanly |

Engineering rules and code conventions are in [CONTRIBUTING.md](CONTRIBUTING.md).
