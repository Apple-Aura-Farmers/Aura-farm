# Contributing

## Branch strategy

Trunk-based, with short-lived branches off `main`.

- **`main` is the trunk.** It always builds and its tests always pass. Nobody pushes
  to it directly; every change arrives through a pull request.
- **One branch per change**, cut from an up-to-date `main`, and deleted once merged.
  Keep them to a few days. A long branch is a conflict waiting to happen, and the
  Xcode project file conflicts badly.
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

1. `Build and test` is green — the app builds and the unit tests pass on an iOS Simulator
2. `Format check` is green — `swift-format lint` is clean
3. `Repo checks` are green — every Swift file is in the Xcode project, and no video or
   oversized file is committed
4. It has no `has-conflicts` label
5. Someone has reviewed it, if the team requires that

Label a pull request `automerge` and it merges itself as soon as those checks pass.

## Making a change

1. Branch: `git switch -c feat/thing main`
2. Add new Swift files **from Xcode** (File > New > File), inside the matching group,
   with the right target ticked. A file that is only on disk never compiles, and CI
   fails the pull request for it.
3. Write a unit test for any decision logic that does not need the camera.
4. Run the tests and the formatter before pushing:

   ```bash
   xcodebuild test -scheme MicroscopeCounter -destination 'platform=iOS Simulator,name=iPhone 17'
   xcrun swift-format format -i -r MicroscopeCounter/Sources MicroscopeCounter/Tests
   ```

5. Open a pull request into `main` and fill in the template.

## What not to commit

- **Raw video.** Clips are training data and live off the repository. Once committed
  they are in the history for good. CI fails on any `.mov`, `.mp4`, `.m4v`, `.avi` or
  `.mkv`, and on any file over 5 MB.
- `xcuserdata/`, `*.xcuserstate`, `DerivedData/` — already ignored.
- Accuracy numbers, soil ratings or scores that have not been measured. See rule 6 in
  [CLAUDE.md](CLAUDE.md).

## Engineering rules

[CLAUDE.md](CLAUDE.md) holds the rules that govern the code: raw footage is never
edited, analysis stays off the main thread, thresholds live in one place and say
whether they are calibrated, and no result ships without the recommended actions
behind it. Read it before a first change.
