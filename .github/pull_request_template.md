## What this changes

<!-- One or two sentences. What is different after this is merged? -->

## Why

<!-- The problem, or the Linear issue: AF-NN -->

## How it was tested

<!-- Simulator, real iPhone on a microscope, or unit tests only. Say which, and say
     if the camera path could not be tested. -->

- [ ] Unit tests pass locally
- [ ] Tried on a real iPhone, on the microscope (say so if the change touches capture)

## Checklist

- [ ] New Swift files were added from Xcode, so they are in `project.pbxproj`
- [ ] `swift-format` run over the changed files
- [ ] No raw video, and no file over 5 MB, committed
- [ ] New decision logic has a unit test that does not need the camera
- [ ] New thresholds are in `CaptureQualityThresholds`, with a comment saying whether
      they are calibrated
- [ ] No accuracy number, soil rating or score that has not been measured
- [ ] UI copy says what the helper should do, in plain words

## Anything a reviewer should know

<!-- Shortcuts taken and their limits, what is left for a follow-up, what was not
     verified. -->
