# Aura Farm

An AI-driven microscopy iOS app that lets a field helper test soil on-site with an
iPhone and a microscope, and get a result and recommended actions during the same
visit instead of waiting weeks for a lab.

*PRD last updated: 27 October 2026.*

## 1. Problem

Farmers and field helpers wait two weeks or more for soil test results from a lab.
During that wait they cannot see whether the soil is getting worse, and they cannot
take follow-up action.

Who experiences it:

- **Field helpers** from institutions who visit farmers — the primary app users
- **Farmers and plot owners** who receive results and act on them
- **Institutions** that manage and support these farmers

## 2. Evidence and insights

What we know:

- Waiting out the lab test period frustrates farmers
- Lab soil tests are costly
- Even with results in hand, farmers often do not know what to do next

Evidence still to be filled in: interview quotes, survey data, and the typical lab
cost and turnaround in our target regions. See
[AF-26](https://linear.app/aurafarmers/issue/AF-26/research-question-which-soil-microscopy-methods-apps-and-labs-already)
for existing labs and tools.

## 3. Hypothesis

If field helpers can test soil on-site with a phone and microscope and get results
immediately, we will:

- cut the time from sampling to action from weeks to the same visit
- reduce testing costs compared with lab tests
- encourage more frequent testing and greater farmer awareness of soil health

## 4. Product goal

Reduce the time it takes for farmers to take action on their soil health.

## 5. Proposed solution

A field helper attaches an iPhone to a microscope, prepares a soil sample following
an in-app guide, and the app uses computer vision to detect microbes that indicate
soil health. It then shows the result and recommends actions to the plot owner.

Starting context and assumptions:

- Target soil: rice paddy
- Magnification: 100x, to be validated
- Candidate indicators: fungi, bacteria, nematodes, protozoa. Good versus harmful
  microbes are being researched in
  [AF-23](https://linear.app/aurafarmers/issue/AF-23/identify-which-microbes-are-best-for-indicating-soil-health-good-and),
  and how they translate to soil health in
  [AF-24](https://linear.app/aurafarmers/issue/AF-24/how-does-the-identified-microbe-affect-how-we-determine-the-soil)
- Hardware: the phone-to-microscope adapter is being evaluated in
  [AF-16](https://linear.app/aurafarmers/issue/AF-16/spike-which-phone-to-microscope-mount-works-for-field-helpers)

## 6. Requirements

The app must be able to:

1. Guide the user through preparing a soil sample
2. Guide the user through attaching the phone and setting up the microscope
3. Capture images of the sample through the microscope
4. Analyse the sample with computer vision and identify the chosen indicators
5. Show results in a form a field helper can explain to a farmer
6. Give recommended actions to the plot owner based on the results

Behaviours and rules that must be explicit:

- Every result comes with recommended actions
- The app always returns some result, even a partial one, and clearly shows its
  confidence or says when a retest or a lab test is needed
- Recommendations are clear and doable by a farmer without technical knowledge
- The app explains what it cannot detect, against what a lab test would find

## 7. User flows

**Flow 1 — onboarding and setup.** Welcome → how the test works → equipment
checklist → step-by-step sample preparation guide → attach phone to microscope and
align → ready to test.

**Flow 2 — perform the test.** Start new test → enter plot and farmer details →
capture microscope images, with guidance on focus and coverage → image quality check
→ AI analysis → results screen.

**Flow 3 — results and recommended actions.** Results summary with an overall soil
health rating → indicator breakdown of good versus harmful microbes found →
recommended actions for the plot owner → save and share the report with the farmer.

### The one flow that reaches the success criteria

1. Onboarding that explains what the app can do, including the camera permission
2. A **Scan** button on the home page, which leads to:
   - the sample preparation guide, with an option not to show it again
   - the camera mounting check
   - recording starts (camera access)
   - a periodic "move the sample" animation, signalled at the start
3. Alerts for unclear images and other bad conditions, naming the human step to take
   (for example, change the lighting)
4. Finish the video by following the given steps
5. Processing in the app, through computer vision
6. Feedback on processing: success, or an error message and a retake screen
7. Results shown in a band
8. Recommendations shown with the results
9. The input, result and recommendation are logged as one record, visible in the
   **History** tab
10. From History, the user can export a chosen record as a PDF

## Features

- Sample preparation and setup guide
- Guided image capture with quality checks
- AI microbe detection
- Soil health result and report
- Action recommendation system

Candidates still to discuss: test history per plot, offline mode for
low-connectivity farms, report sharing by PDF or messaging, local language support,
and an institution dashboard.

## 8. Scope

**In, for the MVP**

- iOS app for field helpers
- Rice paddy soil
- One to three indicators chosen from research
  ([AF-12](https://linear.app/aurafarmers/issue/AF-12/research-synthesis-microscope-visible-soil-health-indicators-and-mvp))
- Onboarding and sample preparation guide
- Image capture through a recommended microscope adapter
- AI detection for the chosen indicators
- A simple soil health result with recommended actions

**Out, for now**

- Android app
- Other soil and crop types
- Chemical tests (NPK, pH and the like)
- Replacing lab tests entirely
- A farmer-facing app and an institution dashboard
- Our own microscope hardware

The team confirms in and out at sprint review.

## 9. Success criteria

These targets are starting points for the team to confirm. None of them has been
measured yet.

| Criterion | Target |
|---|---|
| Time to action | Result and recommendations in the same visit, under 30 minutes from sampling |
| Accuracy | AI detection agrees with expert or lab identification at least 80% of the time for MVP indicators |
| Cost | Cost per test clearly lower than a typical lab test |
| Usability | A field helper completes a full test unaided after onboarding |
| Adoption | Field helpers test plots more often than they did with labs |
| Action | Farmers report they understand the result and take at least one recommended action |

## 10. Open questions and risks

- Which indicators are most reliable at 100x with a phone camera?
  ([AF-23](https://linear.app/aurafarmers/issue/AF-23/identify-which-microbes-are-best-for-indicating-soil-health-good-and),
  [AF-24](https://linear.app/aurafarmers/issue/AF-24/how-does-the-identified-microbe-affect-how-we-determine-the-soil))
- How accurate can computer vision be with limited labelled data?
  ([AF-19](https://linear.app/aurafarmers/issue/AF-19/spike-computer-vision-feasibility-for-our-first-soil-indicator),
  [AF-15](https://linear.app/aurafarmers/issue/AF-15/collect-initial-labeled-soil-microscope-image-dataset))
- Where do recommended actions come from, and who validates them — agronomists,
  institutions?
- Can field helpers prepare samples consistently in the field?
  ([AF-14](https://linear.app/aurafarmers/issue/AF-14/draft-soil-sample-preparation-protocol-for-onboarding-guide))
- Which adapter and microscope do we support?
  ([AF-16](https://linear.app/aurafarmers/issue/AF-16/spike-which-phone-to-microscope-mount-works-for-field-helpers))
- Connectivity on farms: does the analysis need to run on-device?

## 11. Related Linear issues

[AF-12](https://linear.app/aurafarmers/issue/AF-12/research-synthesis-microscope-visible-soil-health-indicators-and-mvp)
research synthesis ·
[AF-23](https://linear.app/aurafarmers/issue/AF-23/identify-which-microbes-are-best-for-indicating-soil-health-good-and)
good and bad microbes ·
[AF-24](https://linear.app/aurafarmers/issue/AF-24/how-does-the-identified-microbe-affect-how-we-determine-the-soil)
microbes to soil health ·
[AF-26](https://linear.app/aurafarmers/issue/AF-26/research-question-which-soil-microscopy-methods-apps-and-labs-already)
existing tools review ·
[AF-14](https://linear.app/aurafarmers/issue/AF-14/draft-soil-sample-preparation-protocol-for-onboarding-guide)
sample prep protocol ·
[AF-15](https://linear.app/aurafarmers/issue/AF-15/collect-initial-labeled-soil-microscope-image-dataset)
image dataset ·
[AF-16](https://linear.app/aurafarmers/issue/AF-16/spike-which-phone-to-microscope-mount-works-for-field-helpers)
mount spike ·
[AF-18](https://linear.app/aurafarmers/issue/AF-18/spike-how-to-capture-usable-images-through-the-microscope-eyepiece-on)
capture spike ·
[AF-19](https://linear.app/aurafarmers/issue/AF-19/spike-computer-vision-feasibility-for-our-first-soil-indicator)
CV spike ·
[AF-20](https://linear.app/aurafarmers/issue/AF-20/design-onboarding-flow-wireframes-setup-sample-prep-guide)
onboarding wireframes ·
[AF-21](https://linear.app/aurafarmers/issue/AF-21/define-soil-health-result-and-report-ux)
result and report UX

---

## What is built today

The repository holds one slice of Flow 2: the capture quality check and raw video
recording. There is no computer vision, no result, and no recommendation code yet,
and none should be added until a labelled dataset and a pilot exist.

- **Quality check** — warns before recording if the live image is too dark, blurry
  or shaky, and keeps Record disabled until the image is usable
- **Raw recording** — saves a clip to `Documents/RawClips` with a JSON sidecar
  holding sample ID, field number, moisture, grams of soil and millilitres scanned
- **Saved clips** — list and playback, in grayscale, without altering the file

Not started: sample preparation guide, mounting check, the move-the-sample prompt,
analysis, results, recommendations, History and PDF export.

## Getting started

```bash
open MicroscopeCounter/MicroscopeCounter.xcodeproj
```

Set your Team under Signing & Capabilities for both targets and replace the
placeholder bundle ID `com.example.microscopecounter`.

Run the unit tests:

```bash
xcodebuild test -scheme MicroscopeCounter -destination 'platform=iOS Simulator,name=iPhone 17'
```

The camera does not work in the Simulator. Test the capture screen on a real iPhone,
with the phone on the microscope.

`.github/workflows/swift-ci.yml` runs that same build and test on every pull request
into `main`.

See [CLAUDE.md](CLAUDE.md) for the engineering rules this repository works under.
