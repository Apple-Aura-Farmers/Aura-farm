# Aura Farm: results screen and AI advice, summary of changes

- **Branch:** `feat/results-screen`, uncommitted on top of `80eeefd`
- **Scope:** the iOS app only. AuraFarmKit is unchanged.

---

## Goal

Field helpers need a results screen that turns a microscope sample into advice they can read aloud to a rice farmer. The advice has to be:

- **grounded** in what was actually counted, not invented
- **safe and cautious:** no verdicts on the soil, no chemicals or doses, no certainty
- **consistent:** the same sample gives the same advice
- **usable without Apple Intelligence**
- **measurable**, so the team can check it before wider use

**The core idea:** the app's code decides the facts and which actions are allowed. Apple's on-device model (Foundation Models) only explains and personalises them.

---

## Part A: What the app now does

### 1. Results screen (placeholder design)
- **Estimate:** a placeholder soil life estimate (good, fair, poor, too few to say, not counted), with low confidence, its reasons, and when to retest.
- **Counts:** the organism count, expandable per class. Two tabs show the detector's class names and the `OrganismGroup` names, because the naming isn't decided yet.
- **Disclaimer:** a small note that nothing is scientifically backed.
- **Advice:** a "What to do next" card.
- **Separate components,** so a future hi-fi design can replace the look without touching the logic.
- **iOS 26:** the deployment target was raised, because Foundation Models needs it.

### 2. Curated advice content (provisional, approved by the team)
- **Notes for all 26 classes** of the team's new detector, researched:
  - **13 interpreted:** the advice reads meaning into them.
  - **12 in a "review pile":** shown in the counts but not interpreted, because the evidence is weak.
  - **Pyrocystis as a trust check:** it's a sea organism, so seeing it suggests a misidentification.
- **The building blocks:**
  - placeholder count bands (low, typical or high per frame)
  - 12 patterns across organisms, such as "euglenoids dominant" or "clean-water algae"
  - 16 approved actions, each with when to suggest it and when not to
  - an approved plain reason for each action
  - a never-say list
- **The source document:** [`docs/advice-content.md`](advice-content.md), written for people, with research links and open items for the team.

### 3. Optional field notes at sample setup
- **New inputs:** farm plot, crop stage and "done recently" (fertilized, drained, added straw and so on). All optional.
- **Renamed field:** "Field" became "Microscope field", so it isn't confused with the farm plot.
- **History:** earlier samples of the same plot are used, so the advice can mention a change.

### 4. How the advice is written
- **Code picks first:** it works out which notes, patterns and actions apply to this sample, and gives the model only those, never the whole catalogue. This also keeps the prompt within the model's small context window.
- **A fixed answer format:** the model returns 1–2 things it noticed, then 2–3 action IDs with a short reason each, then a one-sentence summary.
- **Approved wording:** the screen always shows the team's wording for each action. The model only adds the reasons, the noticed points and the summary.
- **Every step has a reason:** when the model's reason is missing or fails a check, the approved reason is shown instead.
- **Standard advice:** when Apple Intelligence can't run (older phone, setting turned off, unsupported language), the app builds advice from the same approved actions and reasons.

### 5. Safety checks and error handling
- **Checking the model's own words:** they're checked for banned words, amounts or doses, organisms it must not mention, and length.
  - One failing part is replaced with the approved wording.
  - Two or more failures mean standard advice is shown instead, with a note.
- **Errors:**
  - When the model refuses, the language isn't supported or the answer is broken, standard advice is shown with a note saying why.
  - When the model is busy or still getting ready, the card offers "Try again".
- **Timeout:** 30 seconds, a placeholder value.
- **Rule fixes made along the way:**
  - "Keep doing what you're doing" never appears next to a warning.
  - Samples that can't be trusted only get "sample again" actions.
  - Small counts aren't over-interpreted; they show as "few seen".
  - No compost or straw when euglenoids dominate.
  - Actions are trimmed by relevance.
  - "Talk to your extension officer" is always paired with a must-check action, and placed last.

### 6. Stable, quicker advice
- **Saved with the sample:** Apple Intelligence advice is saved (`advice.json`) and shown again when the sample is reopened.
- **Write again:** asks for fresh wording. If that fails, the saved advice stays on screen.
- **Repeatable:** a first answer gets the same wording for the same sample.
- **Progress while writing:** for example "Choosing steps (2 of 3)…". Unchecked text is never shown.
- **Faster start:** the model is loaded when the screen opens.
- **A "Based on …" line** says what the advice used.
- **Older rules labelled:** saved advice from older rules is marked. The content version is worked out from the content itself, so nobody can forget to update it.

### 7. Measuring advice quality
- **Every build:** 21 fixed test samples check that the right actions are offered and the wrong ones aren't.
- **Workbench → Advice check** (debug builds):
  - runs all 21 samples through the real model on a phone
  - auto-grades how well each answer follows the rules: pass, warn or fail
  - exports a CSV with blank columns for people to score accurate, cautious, practical and easy to read aloud, from 1 to 3
- **"Was this useful?" button:** a thumbs up or down under the advice, with reasons. It's saved with the sample (`advice-feedback.json`), and Advice check can export it.
- **Xcode Playground:** optional, for quick prompt experiments.

### 8. Debug and testing tools
- **Result states gallery:** about 27 scenarios, including good, poor, errors, bad model answers and saved advice.
- **"Use Apple Intelligence" switch:** runs the gallery scenarios through the real model on the phone.
- **"What the AI is told":** shows the exact instructions and prompt.
- **Console logging:** raw model answers go to the Xcode console, under the category `advice`.

---

## Part B: How the code achieves it

**Design principle:** deterministic, testable code decides, and the model only phrases. All advice logic in `AuraFarm/Core/Advice/` is pure Swift (Foundation only, no FoundationModels or SwiftUI), so it's fully unit tested and runs without a device.

### 1. Data into the screen
- **`SoilResult`** (`Core/Results`) is the one value the screen reads. It holds:
  - counts by class label and frames kept
  - moisture, plot, crop stage and recent actions
  - whether the sweep stopped early, and the source sweep

  It's built from a saved sweep's manifest. *Goal: one place to change when the data changes.*
- **`SampleDetails`** gains `plotName`, `cropStage` and `recentActions`. They're optional, so older manifests still decode.
- **`PlotHistory.earlierResults`** finds earlier counted sweeps with the same plot name (trimmed, any case). It returns at most 3 as `PastResult` values, newest first.

### 2. Estimate and taxonomy (placeholders)
- **`PlaceholderSoilHealthEstimator`**, behind the `SoilHealthEstimating` protocol:
  - The score is abundance (organisms per frame, up to 60 points) plus diversity (kinds out of 5 known, up to 40 points).
  - The level comes from the score, and confidence is always low.
  - All limits are in `SoilHealthThresholds`, marked PLACEHOLDER.
  - **Known gap:** it still assumes 5 classes.
- **`OrganismTaxonomy` and `ProvisionalTaxonMapping`** drive the two count tabs.

### 3. Advice content as data
- **`OrganismNote` and `OrganismNotes`:** one row per class, with:
  - its use: interpreted, review pile or trust check
  - its role and abundance tier
  - a description, and what high and low counts might suggest
  - a confidence and a review flag

  Lookups ignore case, so both detector models work.
- **`CountBands`:** placeholder per-frame limits for each abundance tier.
- **`AdviceAction` and `AdviceActions`:** the 16 actions, with wording, cost, effort, timing and review need. `fallbackPriority` is the order the app uses when it picks actions itself.
- **`AdviceReasons`:** an approved reason for each action and trigger, listed in `allSentences`.
- **`NeverSay`:** the rules in the instructions, the banned words and the banned phrases.
- **`AdviceContentVersion`:** an FNV-1a hash of all the content plus the instructions. Any change marks older saved advice, and a tripwire test makes sure changes are deliberate.

### 4. Deciding what applies (`AdviceContextBuilder` → `AdviceContext`)
- **Readings:** each count becomes a per-frame figure, then a band.
  - A high reading needs at least 3 organisms.
  - A low reading is only meaningful with at least 20 frames; with fewer, it shows as "few seen".
- **Patterns:** 12 `AdvicePattern` rules over the readings, with two flags:
  - `isConcern` blocks "keep doing what you're doing".
  - `blocksImprovementActions` (set for mixed signals, misidentification and nothing readable) allows only sampling-again actions and keep_notes.
- **Action rules:** each action has "applies when" and "excluded when" conditions. For example, no straw at seedling stage, and no mid-season drain at flowering or when the field is already drained. Each suggested action carries an internal label and an approved reason.
- **Cautions:** the sweep stopped early, few frames were kept, or something may have been misidentified.
- *Goal: the facts and the allowed actions are fixed by code before the model sees anything.*

### 5. Building the prompt (`AdvicePromptBuilder`)
- **`instructions()`:** the role, tone and length limits, how to pick actions by ID, and every never-say rule.
- **`prompt(for:)`:** the sample is described line by line:
  - the sample itself, then the estimate ("from the amount of life only")
  - this sample's totals
  - organism lines, with notes only where they mean something
  - an "Also seen, do not mention" line
  - patterns and history
  - "Actions you may suggest", each with its approved reason and timing
- **`offeredActions(for:)` and `trimmed()`:** cap the actions at 6, keeping the most relevant by priority. Some are protected from trimming:
  - the resample actions
  - `resample_later`, for fair or poor results
  - `talk_extension`, when it's needed
- *Goal: small, relevant input within the 4,096-token window. A budget test keeps the worst case under 7,000 characters.*

### 6. The model's answer and checking it
- **`GeneratedAdvice` and `GeneratedAction`** (`@Generable`):
  - `noticed`: 1–2 points
  - `actions`: 2–3, each an ID restricted to the catalogue plus a `why`
  - `summary`: one sentence

  They're generated in that order, so the evidence comes first.
- **`AdviceOutputChecker`:** catches banned words and phrases (whole words only), doses (a regex plus phrases for amounts without a number), names of organisms it must not mention (plurals included), and over-long text (`AdviceOutputLimits`). It cleans each failing field and reports the findings.
- **`AdviceResponseMapper.map`:**
  1. runs the checks
  2. keeps only offered, unique IDs, at most 3
  3. fills to 2 steps by priority
  4. builds the steps

  It returns an `Outcome` with `droppedPicks`, `findings` and `rejectWhole` (true when more than one field failed).
- **`AdviceStepRules`:**
  - `step(for:why:)` uses the approved wording and timing, plus the model's reason or the approved one.
  - `ensuringExtensionStep` adds `talk_extension` last when a must-check action is present. It drops the least relevant step, always keeping at least one must-check action.
- *Goal: nothing the model writes reaches the screen unchecked, and the action wording is always the approved wording.*

### 7. Running the model (`FoundationModelRecommender`, a final class)
- **`availability`:** the model's own state, plus `supportsLocale()`.
- **`prewarm()`:** keeps one prewarmed session behind a lock. It's used once, then cleared, so every request starts clean.
- **`generate(...)`:**
  - uses greedy sampling (default sampling for Write again)
  - streams the answer and reports `AdviceProgress` from partial snapshots
  - decodes the final answer and maps it
- **`recommend(...)`:** throws `AdviceFailure.useStandardAdvice` when an answer is rejected as a whole.
- **Errors:** every `GenerationError` maps through `ModelErrorKind` to an `AdviceFailure`, either `useStandardAdvice(note)` or `retry(message)`. In debug builds, raw answers, findings and errors are logged.
- **`RuleBasedRecommender`:** standard advice from the same offered actions and reasons. Its summary depends on the patterns, and it uses fixed steps when a sweep wasn't counted.
- **`RecommendationProviding`:** `recommend(for:freshWording:onProgress:)` and `prewarm()`, with default implementations, so stubs and tests stay simple.

### 8. Screen state (`SoilResultViewModel`, `@Observable`, `@MainActor`)
- **The flow:**
  1. show saved advice, if there is any
  2. otherwise check availability and prewarm the model
  3. load the plot history off the main actor
  4. build the context
  5. race the provider against the timeout
  6. handle each kind of `AdviceFailure`
  7. save Apple Intelligence advice
- **State it exposes:** `recommendationState`, `progress`, `modelUnavailableReason`, `savedAt`, `savedFromOlderRules`, `canWriteAgain` and `feedback`.
- **`writeAgain()`** asks for fresh wording. On failure, it keeps the saved advice with a note.
- **`rate(...)`** records feedback.
- **Injected dependencies:** the estimator, recommender, fallback, history, stores, clock and timeout are all injected, so the view model is fully unit tested.
- **UI components** (`SoilHealthCard`, `OrganismCountSection`, `RecommendationCard`, `ScienceDisclaimer`, `ResultActions`) take plain values, so the design can be swapped.

### 9. Storage (`Core/Sweep`)
- **`SavedAdvice` and `AdviceStore` / `FileAdviceStore`:** `advice.json` in the sweep folder. Unknown action IDs still decode.
- **`AdviceFeedback` and `AdviceFeedbackStore` / `FileAdviceFeedbackStore`:** `advice-feedback.json`. Entries are appended, or replaced by ID, and a corrupt file reads as empty.
- **Never touched:** frames, panoramas and `manifest.json`.

### 10. Evaluation (`Core/Advice` and the Workbench)
- **`AdviceEvalCase` and `AdviceEvalCases`:** 21 samples, each with:
  - an expected level
  - patterns that must and must not match
  - actions that must and must not be offered

  They run as unit tests on every build. Known mismatches use `XCTExpectFailure`, rather than changing the rules to pass.
- **`AdviceAutoGrade`:** pass, warn or fail, based on the findings, dropped picks, summary length, reasons that repeat the action, missing noticed points, and slow answers.
- **`AdviceEvalCSV` and `AdviceFeedbackCSV`:** CSV export with proper quoting, and blank rubric columns for people to score.
- **`AdviceCheckView`** (debug): runs the 21 cases one at a time, with a new recommender each time, then shows the results and exports them. It also summarises and exports field feedback.
- **`AdvicePlayground`** (debug): a `#Playground` for prompt experiments.

### 11. Debug tooling (`Features/Results`, `#if DEBUG`)
- **`ResultScenario` and `ScenarioRecommender`:** scripted states, including failures, bad answers, saved advice and simulated progress.
- **`simulatesModelProblem` and `recommender(useLiveModel:)`:** let the gallery switch swap in the real model.
- **`AdvicePromptInspector`:** shows the instructions and prompt, with character counts.
- **In-memory stores** for advice and feedback, used by the gallery.

### 12. Tests and checks
- 327 unit tests passed before soil measurements were added to the advice (Part C). Tests for Part C are written (`SoilInputsTests`, `AdviceUpdateNoteTests`, `AdviceSnapshotTests`, and additions to `AdviceBasisTests`, `AdvicePromptBuilderTests` and `SoilResultViewModelTests`) but none has been compiled or run yet.
- The Release build is clean, and so is `swift-format --strict`.

---

## Part C: soil measurements in the advice (plumbing only)

The soil measurements a field helper records for a farm now reach the advice. **No rules read them yet**, so the estimate, the patterns and the actions offered are exactly what they were, and advice for a farm with no measurements is unchanged (same prompt, same instructions, same content version).

- **Which values:** nitrogen, phosphorus, potassium, pH and organic carbon (`SoilInputs`). Fertilizer is left out: it has no standard, and an amount in the prompt would invite the model to quote a dose. Saving the form again without changing a number is not a change.
- **Into the prompt:** one extra line, only when there are measurements, giving each value, its unit and its band (for example "pH 6.5 (standard)"), marked as background the model must not build advice on. The standards' guidance text is never sent.
- **A copy of what the advice was based on:** `advice.json` gains a `snapshot` (the test, how many earlier samples were used, and the measurements). Advice saved before this has none, which reads as "written without measurements".
- **Automatic rewrite:** when the saved advice's measurements differ from the farm's now, the advice is written again on its own, and a line says why, for example "Updated with the new pH reading." (`AdviceUpdateNote`). If the model can't write it, the earlier advice stays on screen with a note that the measurements changed.
- **"Based on" line:** names the measurements used, for example "…, and soil measurements (N, pH)." Standard advice (when Apple Intelligence can't run) is built from the same rules and does not read the measurements, but the line still names what was available.
- **Next:** rules that combine the microscope counts with the measurements, starting with the pH liming check, need the agronomist's review of the placeholder standards first.

---

## Status and open items

**Done:** Phases 1–6, plus the live-model gallery fix. Everything builds and passes, and nothing is committed.

**Advice-rule problems found by the new test set** (to fix before or after committing):
1. **Straw advice on samples too small to judge.** "Too few to say", short sweeps and sweeps that stopped early still get it. They should only offer "sample again".
2. **Poor results lose "sample again in 2–4 weeks" and the lab test** to straw and compost.
3. **Drained fields get straw advice** even though low counts are expected there. They should get "sample again once flooded" instead.
4. **"Poor twice in a row" trims away the lab test.** It's marked as a known failure in the test set.

**Needs a person or the team:**
- **Test on an iPhone:** progress text, saving and reopening, Write again, Advice check and feedback.
- **Expert review** of every content row marked "Must", the count bands, the approved reasons and the priority order.
- **Decide the naming** (model classes or `OrganismGroup`), and update the estimator for 26 classes.
- **Scoring:** agree who scores the Advice check sheet, and what score is good enough.
- **Release feedback:** decide how feedback is exported from release builds.
