# Contributing

## Branch strategy

Trunk-based, with short-lived branches off `main`.

- **`main` is the trunk.** It always builds and its tests always pass. Nobody pushes
  to it directly; every change arrives through a pull request.
- **One branch per change**, cut from an up-to-date `main`, and deleted once merged.
  Keep them to a few days. A long branch is a conflict waiting to happen.
- **Name the branch for what it does**, using one of these prefixes:

  | Prefix | For |
  |---|---|
  | `feat/` | A new capability, for example `feat/sample-prep-guide` |
  | `fix/` | A bug fix, for example `fix/shake-reading-on-rotation` |
  | `chore/` | Build, CI, docs, dependencies, formatting |
  | `spike/` | Throwaway exploration. Never merged; it informs a later branch |

- **Keep the branch current** by merging `main` into it, not by rebasing a branch
  someone else may have pulled. The `has-conflicts` label appears when the branch
  stops merging cleanly.
- **Squash merge** into `main`, so one pull request is one commit and `main` reads as
  a list of changes.
- **No release branches, no develop branch.** There is one product and one trunk. Add
  one only when a shipped version has to be patched while `main` moves on.

### Merging

A pull request can merge once:

1. `Build and test` and `AuraFarmKit tests` are green — the app builds and every unit
   test passes
2. `Format check` is green — `swift-format lint` is clean
3. `Repo checks` are green — every Swift file is inside a target folder, and no video or
   oversized file is committed
4. It has no `has-conflicts` label
5. Someone has reviewed it, if the team requires that

Label a pull request `automerge` and it merges itself as soon as those checks pass.

## Making a change

1. Branch: `git switch -c feat/thing main`
2. Put new Swift files inside the right target folder (`AuraFarm/`, `AuraFarmTests/`, …),
   from Xcode or on disk. The folders are synchronized with the project, so the file is
   in that target with no project edit. A Swift file outside every target folder never
   compiles, and CI fails the pull request for it.
3. Write a unit test for any decision logic that does not need the camera.
4. Run the tests and the formatter before pushing:

   ```bash
   xcodebuild test -scheme AuraFarm -destination 'platform=iOS Simulator,name=iPhone 17'
   swift test --package-path AuraFarmKit
   xcrun swift-format format -i -r AuraFarm AuraFarmTests AuraFarmKit
   ```

5. Open a pull request into `main` and fill in the template.

## What not to commit

- **Raw captures.** Sweeps of frames, and any video, are training data and live off the
  repository. Once committed they are in the history for good. CI fails on any `.mov`,
  `.mp4`, `.m4v`, `.avi` or `.mkv`, and on any file over 5 MB. Frames are small enough
  to slip under that, so keep `Documents/FrameSets` off the repository yourself.
- `xcuserdata/`, `*.xcuserstate`, `DerivedData/` — already ignored.
- Your signing team. It goes in `Config/Local.xcconfig`, which is ignored. Setting it under
  Signing & Capabilities writes it into `project.pbxproj` instead; do not commit that.
- Accuracy numbers, soil ratings or scores that have not been measured. See rule 6
  below.

## Engineering rules

Read these before a first change. They are not style preferences; each one exists
because breaking it costs data or credibility.

1. **Never overwrite or edit raw video.** Raw footage is the source for training data.
   Processing steps work on copies.
2. **Keep analysis off the main thread.** Frames arrive on a background queue; only
   publish UI state on the main queue.
3. **Do not hold on to camera buffers.** Keep at most one previous frame for shake
   estimation.
4. **Keep detection logic out of views.** Views read state from the model; thresholds
   and rules live in `AuraFarm/Core/`.
5. **Thresholds are data, not magic numbers.** Put new ones in
   `CaptureQualityThresholds`, with a comment saying whether they are calibrated.
6. **Do not claim accuracy.** No accuracy number in code, UI or docs until it is
   measured against expert counts, with train and test split by video or sample, never
   by frame. A target agreed in planning is a target, not a finding.
7. **Calibration matters.** Counts need real sizes. When the counting stage is built,
   pixel-to-µm calibration with a stage micrometer clip is required per phone and lens
   setup.
8. **No soil verdict without the actions behind it.** Do not ship a rating, score or
   band on its own. Every result carries recommended actions, states its confidence,
   and says when a retest or a lab test is needed.

## The soil report format

Field helpers and the program manager share one phone and one set of farm records, so a
finished sweep is saved straight into them. The `.aurafarm` soil report in `AuraFarmKit`
remains for sharing a test off the phone and importing one from another phone. Change it
with care: two phones are rarely updated on the same day.

- Add new fields as optionals, so a report from an older phone still opens.
- Raise `SoilReport.currentSchemaVersion` only for a change an older reader cannot ignore.
  An older app then says the report needs an update instead of failing on it.
- Keep it Foundation only, so its tests run with `swift test` and nothing else.

## UI copy

The users are field helpers, not scientists. Short, plain sentences that say what to
do ("Add more light under the slide"), not what the algorithm measured. Never say
"healthy" or "no life in soil": this app does not judge soil, and an empty slide
usually means a sampling problem. A result the helper has to explain to a farmer has
to be sayable out loud.

## Code conventions

- Small files, one main type per file, names that say what the thing does
- `final class` or `struct` by default
- A doc comment on anything with a non-obvious threshold or unit
- A unit test for any new decision logic that does not need the camera
- No force unwraps outside previews and tests
