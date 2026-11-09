# Aura Farm

An iOS app that turns an iPhone and a microscope into an on-site soil test, and keeps the
results by farm and field with a fertilizer plan for each field.

Two people share one phone, each with their own screens. A toggle at the top of every
screen switches between them:

- **Field helper** — prepares the sample, runs the sweep, gets the result, files it under
  the field it came from, and opens that field's plan to explain it to the farmer. Sees
  farms, fields and plans but does not change them.
- **Program manager** — sets up farms and fields, draws them on the map, types in NPK
  results, keeps the seasons, and files any test the helper left in the inbox.

The toggle is a placeholder for sign-in: anyone can switch.

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
- **Saved to the farm records** — the result screen saves the test into the records both
  roles share, as soon as it opens, and asks which field it came from. Saving the same
  sweep twice is recognised and skipped.
- **Share report** — a saved sweep can still be shared as a `.aurafarm` soil report by
  AirDrop, Files or Mail, to move it to another phone or keep a copy.
- **Export** — frames can be copied off the phone with the Files app.

**Farm records** (the program manager changes them; field helpers look them up)

- **Farms and fields** — each farm with its farmer, village and notes, and the fields
  (paddies) it is split into.
- **Inbox** — tests a helper saved without picking a field wait here to be filed. From
  here the manager can also add sweeps saved on the phone before the records existed, or
  import `.aurafarm` files from another phone.
- **Soil tests** — file each test under its field, then see what was counted, as a chart
  and a table, with the sample details, how it was counted, the slide and notes.
- **Trends** — organisms counted per field over time, on each farm's page.
- **Field page** — tap a field on its farm's page to see everything
  about it in one place: what to do, its NPK results, the latest microscope count, and
  both trends.
- **Satellite map** — on a field's page, choose **Draw Boundary** and tap the paddy's
  corners on satellite imagery; search for the farm's village to get there. The outline's
  area can replace the field's typed-in area, so the fertilizer doses for the field use the
  real size. The farm's page shows every drawn field on one map; tap a name to open it.
  Imagery comes from Apple Maps and needs an internet connection.
- **NPK results** — type in N, P and K from the paddy soil test kit (PUTS), which gives a
  class of low, medium or high, or from a lab report. A lab value in % total N, or in mg
  P₂O₅ or K₂O per 100 g with 25% HCl, is classed for you; in any other unit, pick the class
  the report gives. Add the pH, organic carbon (C-organik) from a lab, and whether last
  season's straw went back into the field.
  NPK is kept apart from the microscope soil tests: it comes from a different test, on a
  different day, and never arrives in an `.aurafarm` report.
- **Seasons** — each field's growing seasons: the rice variety, the transplanting and
  harvest dates, and the yield in t/ha, or a total harvest in kg turned into t/ha from the
  field's area. Record each fertilizer the farmer put on, with its amount for the field;
  the current season shows urea, SP-36 and KCl put on against the plan. Once there are two
  harvests, a chart shows the yield by season against the 5 to 7 t/ha the doses assume.
- **What to do** — from the latest NPK results, a fertilizer plan in urea, SP-36 and KCl,
  per hectare and for the whole field when its area is entered, with when to put each on,
  as real dates once the current season's transplanting date is in. Then any pH action,
  organic matter when organic carbon is below 2%, a confidence (low, fair or good) with the reasons for it, and when
  to test again or send a sample to a lab.

The fertilizer plan follows the national paddy soil test guide for irrigated rice yielding
about 5 to 7 t/ha, as published, and is not calibrated by this team. The thresholds, doses
and their sources are in `AuraFarmKit/Sources/AuraFarmKit/Advice/`. The microscope counts
never change a dose: they are raw and not calibrated, so they only ask for a slide to be
checked when nothing was counted, or for a repeat when a count falls sharply against a test
prepared the same way. The app still gives no soil health rating.

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
  of place makes the whole picture misleading. A shift of more than 0.4 of a frame is
  therefore treated as a failure to line up: the sweep keeps its frames and says they
  were not joined, rather than showing a panorama that cannot be trusted. That number
  comes from cutting one photograph into twelve overlapping fields and joining them
  back, where every frame's right place is known; it is not measured on a microscope.
- A frame is kept once the view has moved far enough from where the last one was taken,
  measured against that frame rather than added up along the way, and only while the
  slide is moving slowly enough for the next frame to be lined up against it. Move it
  far enough in one go and the last kept frame drops out of reach: the next usable frame
  then starts a fresh run, and the two runs do not join.
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

Requires Xcode 16 or later. The app runs on iOS 17 or later, iPhone, portrait only. No
third-party dependencies.

| Scheme | Builds |
|---|---|
| `AuraFarm` | The iOS app and its tests |

Run the unit tests:

```bash
xcodebuild test -scheme AuraFarm -destination 'platform=iOS Simulator,name=iPhone 17'
swift test --package-path AuraFarmKit
```

The simulator name has to match a runtime installed on your machine;
`xcrun simctl list devices available` lists them.

The camera does not work in the Simulator. Test the capture screen on a real iPhone,
mounted on the microscope.

### Try the whole flow on one phone

No microscope needed: a recorded microscope video goes through exactly the pipeline the
camera does.

1. **Program manager:** run the `AuraFarm` scheme on your iPhone and pick **Program
   manager** at the top. On **Farms**, add a farm and a field. Put a microscope recording
   in Photos.
2. **Field helper:** switch to **Field helper**. Tap **New Test**, open the preparation
   guide if you need it, type a sample name, and use a recorded video, or with a
   microscope start the camera and follow the arrows.
3. **Result:** when the sweep finishes, the result shows what was counted and is already
   saved. Pick the field under **Farm records**, then open **What to do** for the plan.
4. **Program manager:** switch back. Open the field, choose **Add NPK Results**, enter
   the kit's classes or a lab's values, and the field page shows the fertilizer plan.

## Repository layout

```
AuraFarm.xcodeproj      The Xcode project. Target folders are synchronized: a file
                        added to one on disk is in that target, no project edit needed.
AuraFarm/               The iOS app
  App/                  App entry point, with the farm records store
  Core/
    Imaging/            Frame analysis, quality check, panorama stitching
    Sweep/              Sweep rules, recorder, saved-sweep library, sample details
    Detection/          Core ML organism detector, tally, benchmark
  Records/
    Models/             SwiftData records: Farm, Field, SoilTest, OrganismCount,
                        NutrientTest, Season, FertilizerApplication
    Services/           Saving sweeps and importing reports, handing a field to the advisor
  Features/             SwiftUI screens, one folder per feature
    Roles/              The role toggle and each role's home
    Home/  SampleSetup/  Capture/  SweepLibrary/  RecordedSample/  Workbench/
    Farms/  Fields/  Map/  Seasons/  SoilTests/
  Resources/            Core ML model
AuraFarmTests/          Unit tests for the app
AuraFarmKit/            Swift package the app is built on: the .aurafarm soil report format,
                        Advice/, the NPK thresholds, fertilizer doses and advisor, and
                        Mapping/, field outlines and their area
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
| `AuraFarmKit tests` | Runs the shared package's unit tests |
| `Format check` | `swift-format lint`, settings in `.swift-format` |
| `Repo checks` | Every Swift file is inside a target folder; no video or file over 5 MB |
| `Conflict check` | Labels the pull request `has-conflicts` when it stops merging cleanly |

Engineering rules and code conventions are in [CONTRIBUTING.md](CONTRIBUTING.md).
