# Aura Farm: Advice content, Phase 1

**Status:** Approved 9 November 2026. Rules updated 9 November 2026 (Phases 3 to 6), see 'Rules for the model'. This is the provisional content the on-device advice (Apple Foundation Models) is built from.

**What this is:** the facts, rules and wording the AI advice may use. The model explains and personalises this content; it does not invent its own.

**What this is not:** checked science. Every row is a best-effort draft from published protist ecology, mostly wastewater, river and lake studies. Paddy-specific research is thin, and the detector names genera or groups, while indicator meanings often differ by species. Nothing here rises above "Medium" confidence. Rows marked **Must** need an expert to review them first.

**Detector:** written for the team's new 26-class model, which is not yet merged. The bundled 5-class model (euglena, paramecium, stentor, volvox, vorticella) is a subset, so the same content works for both.

**In the code:** this content lives in `AuraFarm/Core/Advice/`. The exact thresholds and matching rules are defined there. A change to either one must be made in both places.

---

## Settings

| Setting | Value | Status |
|---|---|---|
| Language | English | Provisional |
| Reader | The field helper, reading aloud to the farmer | Provisional |
| Tone | Calm, practical, encouraging; never alarming | Proposed |
| Reading level | Short everyday words; one idea per sentence | Proposed |
| Length | Summary of 1–2 sentences (up to ~30 words); 2–3 actions of one sentence each (up to ~20 words) | Proposed |
| Crop stage at sample setup | Optional input, used in later phases | Provisional |
| Changes to the soil health estimator | Handled separately, not part of this work | Agreed |

### Rules for the model
- Use only the organisms in **Table A1, "Counts toward the advice"**. Organisms in the review pile and the trust check still show in the counts on screen. The prompt lists them as "also seen, not interpreted", and the model must not comment on them.
- Never say that something "was not found" for an organism in the review pile or the trust check.
- Nematode counts include helpful and harmful kinds. The model must never call them good or bad.
- Only compare a result with samples from the same field, at a similar point in the season, in the same flooded or drained state.
- Pick actions only from **Table B**. Never invent one.
- Class names are kept as data, so the advice keeps working when the detector model changes.
- When a sample can't be trusted (possible misidentification, nothing that can be read, or mixed signals), only sampling-again actions and keep_notes are offered.
- A low count is only interpreted when at least 20 frames were looked at, and a high count needs at least 3 organisms. Both are placeholders.
- The rough estimate reflects the amount of life only. When a pattern raises a concern, the advice must not call the result good.
- The model picks actions by id and writes only a short reason for each. The action wording shown on screen is always the approved wording in Table B.
- When the app picks actions itself (standard advice, or to fill in), it uses a fixed priority order, starting with sampling again: resample_trust, resample_fresh, resample_flooded, check_root_pests, refresh_water, review_fertilizer, alternate_wet_dry, return_straw, add_compost, stop_burning, green_manure, keep_practice, resample_later, lab_test, talk_extension, keep_notes. (Placeholder order.)
- When more than 6 actions apply, the 6 most relevant are offered, using the priority order above.
- Every step shows a reason. The model is given the approved reason from Table B2 and writes its own version; the approved reason is shown when the model's is missing or fails a check.
- The app checks the model's own words (what it noticed, its reasons and its summary) against Table C, for amounts or doses, for organisms it must not mention, and for length. A failing part is removed or replaced with the approved wording. If two or more parts fail, standard advice is shown instead.
- "Sample again in 2 to 4 weeks" is always offered for a fair or poor result, and "Talk to your local extension officer" whenever a Must action is offered or the result is poor; trimming never removes them.
- When "Talk to your local extension officer" has to be added to three steps, it goes last, and the least relevant other step is dropped, never a resample and never the last Must action.
- Apple Intelligence advice is saved with the sample and shown again when the sample is reopened; "Write again" asks for new wording. Standard advice isn't saved. Saved advice written with older rules says so.
- The farm's soil measurements (nitrogen, phosphorus, potassium, pH, organic carbon) reach the prompt as one background line: each value, its unit and its band. The model is told not to give advice from them, and no rule reads them yet, so the estimate, patterns and actions offered are the same with or without them. Fertilizer and the standards' guidance text are never sent. Rules that combine the microscope counts with the measurements (starting with the pH liming check) wait for an agronomist to review the placeholder standards.
- Each saved piece of advice keeps a copy of the measurements it was written with. When the farm's measurements differ from that copy, the advice is written again automatically, with a line such as "Updated with the new pH reading." If Apple Intelligence can't write it, the earlier advice stays on screen with a note. The "Based on" line names the measurements used.

---

## Table A1: Organisms

**Role** is what each organism does in the food web, so the sample can be read as a whole: bacteria-feeder, predator, alga (makes its own food from light), or mixed feeder.

**Check:**
- **Must:** a key claim, or one we're unsure of; an expert needs to review it.
- **Should:** reasonable, but worth confirming.
- **Light:** fairly standard.

### Counts toward the advice (13)

| Class | Role | What it is | A high count might suggest | Low or none might suggest | Confidence | Check |
|---|---|---|---|---|---|---|
| Amoeba (naked amoebae) | Bacteria-feeder | A shapeless, slow-crawling single cell | Lots of bacterial grazing. In soil, amoebae are a main driver of releasing nitrogen to plants. | Hard to spot, so a low count is often just missed ones | Medium | Should |
| Arcellinida (testate amoebae) | Bacteria-feeder | An amoeba living inside a small shell | Moist soil rich in organic matter. They were about 5× more common under organic farming in one trial. | Drier soil, or less organic matter | Medium | Should |
| Nematode | Mixed (feeding type unknown) | A tiny worm | An active food web, but some nematodes are rice root pests. The app can't tell which kind, so a high count is neither good nor bad on its own. | Not a concern on its own | Medium (direction unclear) | Must |
| Monogononta (monogonont rotifers) | Bacteria and particle feeder | A tiny animal with a crown of beating hairs | Nutrient enrichment: rotifers respond strongly to added nitrogen and phosphorus in fresh water | Not a concern on its own | Medium | Should |
| Paramecium | Bacteria-feeder | A fast, slipper-shaped ciliate (a single cell covered in tiny hairs) | Plenty of bacteria from rotting matter. It tolerates dirty, low-oxygen water, so lots of them isn't a good sign on its own. | Little organic matter, or the sample dried out | Medium | Should |
| Vorticella | Bacteria-feeder | A bell-shaped cell on a spring-like stalk | Enough oxygen and good bacterial activity | Low oxygen | Medium | Should |
| Coleps | Mixed (eats almost anything) | A small barrel-shaped ciliate with a plated shell | Moderately enriched water. It's rated as tolerating moderate pollution. | Not a concern on its own | Medium | Should |
| Didinium | Predator | A barrel-shaped ciliate that hunts Paramecium | There's a predator level in the food web, which means enough prey to support it | Normal; it's naturally scarcer than its prey | Medium | Should |
| Euglena | Mixed (light plus dissolved food) | A small green swimmer with a whip-like tail | Nutrient-rich, still water; possibly too much nitrogen. Linked to nitrogen in rice paddies. | Normal | Medium | Must |
| Phacus | Mixed (light plus dissolved food) | A flat, leaf-shaped relative of Euglena | Same as Euglena: high nutrients. Named as a high-nutrient indicator in one study. | Normal | Medium | Should |
| Lepocinclis | Mixed (light plus dissolved food) | A spindle-shaped relative of Euglena | Same as Euglena. The evidence is for euglenoids as a group, not this genus. | Normal | Medium (group evidence only) | Should |
| Dinobryon | Alga that also eats bacteria | A branching golden alga that lives in little cups | Low nutrients, especially low phosphorus: it does well in clean, nutrient-poor lakes | Normal | Medium (lake evidence) | Must |
| Micrasterias | Alga | A flat, star-shaped green desmid (a kind of single-celled green alga) | Clean, low-nutrient, slightly acidic water | Normal | Medium (fen and pond evidence) | Must |

### Review pile: kept for the team to look at, but it doesn't affect results (12)

| Class | Why it's here |
|---|---|
| Stentor | The evidence conflicts: sensitive to ammonia and scarce in poor conditions, but one source says it lives in low-oxygen water. Nothing found for paddies. |
| Volvox | Comes and goes quickly; no paddy evidence found |
| Hypotrichida | Often the main ciliates in soil, but no evidence was found of what they indicate |
| Digononta (bdelloid rotifers) | Very widespread and survive drying, so they don't signal much |
| Frontonia | Only one river study, where it appeared at less polluted sites |
| Closterium | Meaning depends on the species; some indicate high nutrients, and the genus is tolerant |
| Pinnularia | Favours acidic soil, but is also described as broadly tolerant |
| Ceratium | Lake plankton; nothing found for paddies |
| Peridinium | Nothing usable found |
| Collodictyon | Rare, and eats algae; no indicator meaning found |
| Cylindrocystis | Nothing found |
| Pleurotaenium | Nothing found |

### Trust check (1)

| Class | How it's handled |
|---|---|
| Pyrocystis | A sea organism, so in a freshwater paddy sample it's probably a misidentification. It's left out of the advice. If it's a large share of the sample, the advice suggests sampling again, because the labels may not be reliable. |

---

## Table A2: Count bands (placeholders)

These are **guesses**, there only so the advice can say "a lot" or "a little". Counts per frame depend on how much the slide was diluted, which isn't standardised yet. They will be replaced with figures from the team's own test sweeps of 10–20 fields considered typical.

| How common | Classes | Low (per frame) | Typical | High |
|---|---|---|---|---|
| Common | Paramecium, Amoeba, Euglena, Vorticella, Nematode | below 0.3 | 0.3–2 | above 2 |
| Moderate | Arcellinida, Monogononta, Coleps, Phacus, Lepocinclis | below 0.1 | 0.1–1 | above 1 |
| Scarce | Didinium, Dinobryon, Micrasterias | — | below 0.3 | above 0.3 |

---

## Table A3: How moisture changes the reading

| Condition | Effect | Advice should... |
|---|---|---|
| Flooded | Swimming cells are active. This is the "normal" reading for a paddy. | Read the counts as given |
| Drained | Many cells go dormant and don't show up, so counts drop even in good soil. Drained paddies are dominated by fungi, flooded ones by protozoa. | Treat low counts more gently, and suggest sampling again once the field is flooded before acting |
| Recently changed (just drained or just flooded) | Populations take days to settle | Suggest waiting about a week and sampling again. *(Needs a new input; left out until crop stage and recent actions exist.)* |

---

## Table A4: Patterns across organisms

### Count toward the advice

| Pattern | What it might suggest | Confidence |
|---|---|---|
| Several roles present: bacteria-feeders, a predator (Didinium) and algae | A varied, layered food web: the most encouraging pattern | Medium |
| Euglenoids dominant (Euglena, Phacus, Lepocinclis), few ciliates | Still, nutrient-heavy water; possibly too much nitrogen | Medium |
| Clean-water algae present (Dinobryon, Micrasterias), few euglenoids | Lower nutrients, cleaner water | Medium |
| Euglenoids high and clean-water algae present | Contradictory; don't draw a conclusion, sample again | Light |
| Didinium present with Paramecium low | The predator may be eating them down, so low Paramecium is not a sign of poor soil here | Medium |
| Plenty of Vorticella | Enough oxygen | Medium |
| Plenty of testate amoebae (Arcellinida) | Moist soil rich in organic matter | Medium |
| Nematodes high | Ambiguous: could be helpful worms or root pests | Rule |
| Low counts in a drained field | Expected, not alarming | Medium |
| Only one kind found | Too narrow to judge; probably a sampling issue | Light |
| Nothing at all | A sampling or slide problem | Light |
| Pyrocystis is a large share of the sample | The detector's labels may be off; sample again | Rule |

### Review pile: doesn't affect results
- Paramecium or Coleps dominant with little Vorticella → heavy decay, low oxygen. Makes sense from the wastewater evidence, but nothing was found for paddies.
- Any pattern relying on Volvox, Stentor or Hypotrichida.
- Ciliates fall about a month after flooding, then recover. From one small lab study.

---

## Table B: Approved actions

The model picks 2 or 3 of the actions that apply and writes one sentence on why each fits this sample. It can't add its own.

| ID | Wording (to read aloud) | When it applies | Cost | Effort | Timing | Don't suggest when... | Check |
|---|---|---|---|---|---|---|---|
| resample_fresh | "Make a fresh slide and sweep again before changing anything." | Too few to say; stopped early; few frames kept | None | Low | Now | — | Light |
| resample_flooded | "Sample again once the field is flooded. Dry soil hides many organisms." | Drained sample with a low or fair result | None | Low | Next flooding | Already flooded | Should |
| resample_later | "Sample this field again in 2 to 4 weeks, the same way, to see if it changes." | Any fair or poor result | None | Low | 2–4 weeks | — | Light |
| resample_trust | "Sample again; some organisms may have been misidentified." | Pyrocystis is a large share of the sample | None | Low | Now | — | Light |
| keep_practice | "Keep doing what you're doing in this field." | Good result | None | None | — | Poor result; any concern pattern (euglenoids dominant or high, mixed signals, nematodes high, possible misidentification, nothing that can be read, only one kind) | Light |
| return_straw | "Work leftover rice straw back into the soil instead of burning it." | Low abundance or low diversity | None | Medium | After harvest | Just before transplanting (fresh straw in a flooded field can harm young plants); euglenoids high; clean-water algae dominant, euglenoids dominant | Must |
| stop_burning | "Avoid burning straw. It removes food for soil life." | Low abundance | None | Low | After harvest | — | Should |
| add_compost | "Add well-rotted compost or manure if you have it." | Low abundance | Low | Medium | Before planting | Euglenoids high (likely too many nutrients already); clean-water algae dominant, euglenoids dominant | Must |
| green_manure | "Between seasons, grow a cover crop like beans and dig it in." | Low diversity or abundance | Low | Medium | Next fallow | Mid-season | Should |
| refresh_water | "Try not to let water sit still for long. Let fresh water flow in where you can." | Euglenoids high or dominant | None | Low–Medium | This week | Water is scarce | Must |
| alternate_wet_dry | "Ask about draining the field briefly mid-season, then reflooding. It lets air into the soil." | Euglenoids dominant | None | Medium | Mid-season | Flowering (water stress hurts yield); unreliable water supply | Must |
| review_fertilizer | "Check with your extension officer whether you're using more fertilizer than the crop needs." | Euglenoids dominant | Saves money | Low | Before next application | — | Should |
| check_root_pests | "If plants look stunted or roots have swellings, ask your extension officer about root worms." | Nematodes high (always "check", never a diagnosis) | None | Low | This week | — | Should |
| talk_extension | "Talk to your local extension officer before making big changes." | Poor result; always shown alongside an action marked Must | None | Low | Before acting | — | Light |
| lab_test | "If the result stays low, send a soil sample to a lab." | Poor result twice in a row; poor result before a big change | Medium | Low | After a second poor result | First reading only | Light |
| keep_notes | "Write down what you did in this field, so the next sample can be compared fairly." | Every result | None | Low | Now | — | Light |

## Table B2: Approved reasons

Every step on screen comes with a reason. Standard advice shows these reasons, and they're given to the model to build on. If the model's own reason fails a check, the approved one is shown instead. **Placeholder copy for the team to review.**

| Action (trigger) | Reason |
|---|---|
| resample_fresh: level too few to say | Too little was seen to judge the soil. |
| resample_fresh: nothing that can be read | What was seen can't be read yet. |
| resample_fresh: mixed signals | The signs in this sample point different ways. |
| resample_fresh: only one kind | Only one kind of organism was seen, which is too narrow to judge. |
| resample_fresh: sweep stopped early | The sweep stopped before it finished. |
| resample_fresh: few frames kept | Only a small part of the slide was looked at. |
| resample_flooded | The field was drained, and dry soil hides many organisms. |
| resample_later | One sample can vary, so a second one shows whether this holds. |
| resample_trust | Some organisms in this sample may have been misidentified. |
| keep_practice | Plenty of soil life was seen, of several kinds. |
| return_straw: low abundance | Not much soil life was seen, and straw is food for it. |
| return_straw: low diversity only | Only a few kinds of organism were seen, and straw feeds a wider range. |
| stop_burning | Little soil life was seen, and burning removes the food it needs. |
| add_compost | Not much soil life was seen, and compost feeds it. |
| green_manure: low abundance | Little soil life was seen, and a cover crop adds food for it. |
| green_manure: low diversity only | Only a few kinds of organism were seen, and a cover crop adds food for more. |
| refresh_water | Many Euglena-type organisms were seen, which often means still, nutrient-rich water. |
| alternate_wet_dry | Still, nutrient-rich water can be short of air, and a short drain lets air in. |
| review_fertilizer: fertilized recently | Seen soon after fertilizing, this can mean more nutrients than the crop needs. |
| review_fertilizer: otherwise | A sample like this can mean more nutrients than the crop needs. |
| check_root_pests | Many tiny worms were seen. Some kinds feed on rice roots, and the app can't tell which. |
| talk_extension: poor result | Little soil life was seen, so an expert view helps before acting. |
| talk_extension: must-check action suggested | Some of these steps are bigger changes, so it's worth asking first. |
| lab_test | This plot looked low twice in a row. |
| keep_notes | Notes make the next sample easier to compare. |
| Not counted (fixed steps) | Counting didn't run on this sweep. |

---

## Table C: Never-say list

| Banned | Reason |
|---|---|
| "Healthy" or "unhealthy" in any form | Project rule (CONTRIBUTING.md); the estimate can't support it |
| Words of certainty: "definitely", "proves", "guaranteed", "will improve" | The counts are rough and unchecked |
| Any chemical, pesticide, product or brand name | Safety and liability risk |
| Amounts, doses or rates ("2 bags per hectare") | Can't be backed up, and could cause harm |
| Yield or profit promises | Not something these counts can predict |
| Anything about water being safe to drink, or human or animal health | Out of scope and dangerous |
| Facts not in the prompt (pH, nitrogen levels, weather, disease names) | The model would be inventing them |
| Organisms the detector doesn't know | It can only see its own classes |
| "Not found" for organisms in the review pile or the trust check | They aren't interpreted, so saying they're absent would mislead |
| Calling nematodes good or bad | The app can't tell helpful worms from root pests |
| Blaming the farmer ("you did wrong") | Tone: the helper has to keep the farmer's trust |

The app checks the model's text against this list automatically; the word list in the code is a placeholder the team can extend.

Amounts written without a number ("a couple of bags", "a sack of") are also caught.

---

## How the advice is checked

- **Every build:** 21 fixed test samples (AuraFarm/Core/Advice/AdviceEvalCases.swift) check that the right actions are offered and the wrong ones aren't.
- **On a phone, after any prompt or content change:** Workbench → Advice check runs all 21 through Apple Intelligence, grades how well it follows the rules (pass, warn, fail), and exports a sheet. In the sheet, people score each answer from 1 to 3 for accurate, cautious, practical and easy to read aloud. The automatic grade checks rule-following only, never whether the advice is right for the soil.
- **From the field:** helpers can mark advice as useful or not, and say why. Workbench → Advice check exports all feedback.
- **Content version:** worked out from the content itself, so any change marks older saved advice as written with older rules.

---

## Open items for the team

1. **Expert review** of every row marked Must, especially:
   - euglenoids as a sign of too many nutrients
   - Dinobryon and Micrasterias as clean-water signs in a paddy
   - nematode handling
   - `return_straw` timing, `add_compost` exclusions and `alternate_wet_dry`
2. **Count bands:** replace the A2 placeholders using test sweeps from fields considered typical.
3. **Local fit:** is any action unrealistic for the farmers we work with (cost, water access, local practice)? Is anything common locally missing?
4. **Naming:** confirm whether results use model classes or OrganismGroup groups. The new model includes all five OrganismGroup groups, but the 21 other classes still need a group.
5. **Estimator:** it currently assumes 5 known classes. With 26 classes the diversity score changes completely. This is separate work, but needed when the new model is merged.
6. **Thin advice:** some samples get only two steps, one of them "keep notes" (for example, many nematodes, or a fair sample with no other signals). Decide whether more actions are needed for these cases.
7. **Banned words and dose checks:** the lists are placeholders. Dose detection looks for a number followed by a unit, so unusual phrasing can slip through.
8. **Approved reasons (Table B2):** review the wording. The model builds on these, and they are what farmers see in standard advice.
9. **Scoring:** agree who scores the Advice check sheet, and what average score is good enough before wider use.
10. **Feedback export in release builds:** today only debug builds can export feedback. Decide how feedback reaches the team once helpers use release builds.

---

## Sources

**Euglenoids**
- Saprobic sequence within the genus Euglena (NIES reference): https://www.nies.go.jp/chiiki1/protoz/refere/id2999/2671.htm
- NC DEQ – Euglenoids: https://deq.nc.gov/water-resources/euglenoids/open
- Euglenoids in a Burkina Faso drinking water source (Phacus): https://www.nisc.co.za/products/abstracts/36579/diversity-of-euglenoids-in-a-drinking-water-source-in-burkina-faso-west-africa-implications-for-sustainability-and-water-quality
- Red euglenoid blooms in Brazilian rice fields: https://core.ac.uk/works/115481533
- Korean paddy Euglena survey: https://koreascience.kr/article/JAKO199234056678171.do
- Nitrogen fertilizers and paddy protists (2024): https://phys.org/news/2024-01-nitrogen-based-fertilizers-differentially-affect.pdf

**Ciliates**
- Danube ciliate saprobity (Paramecium, Coleps): https://rcin.org.pl/ibd//Content/12047/PDF/WA488_17684_P1825-T32-nr1_AP.pdf
- Ciliates in activated sludge: https://ciliateguide.myspecies.info/ciliates-activated-sludge
- Wastewater organism identification: https://www.microscopeworld.com/blog/wastewater-treatment-organism-identification/
- Protozoa as indicators of mixed liquor saprobic conditions: https://kh.aquaenergyexpo.com/wp-content/uploads/2023/02/Protozoa-as-Bio-indicators-of-Mixed-Liquor-Saprobic-Conditions.pdf
- Stentor coeruleus ammonia sensitivity: https://pmc.ncbi.nlm.nih.gov/articles/PMC3464382
- Stentor photography notes: https://canadiannaturephotographer.com/stentor.html
- Polish river ciliates (Frontonia): https://www.rcin.org.pl//Content/159825/PDF/KR038_167014_r1981-t23-no4_AH-Wiackowski-319-329.pdf
- Brazilian stream ciliates: https://scielo.br/j/bjb/a/Tt7brrTsbyt7DmH7BBJJsPG/?lang=en
- Didinium (MicrobeWiki): https://microbewiki.kenyon.edu/index.php/Didinium
- Didinium–Paramecium predator-prey cycles and temperature: https://peerj.com/articles/9377

**Paddy and soil protists**
- Rice field ciliates after flooding: https://dx.doi.org/10.1007/s00374-003-0644-z
- Winter-flooded paddy ciliates: https://www.protistology.jp/journal/jjp39/25Kameyama.pdf
- Paddy microeukaryotes, flooded vs drained: https://www.jstage.jst.go.jp/article/jsme2/29/1/29_ME13128/_html
- Soil protists in rice fields review (2023): https://springerlink.bibliotecabuap.elogim.com/doi/10.1007/s00374-023-01705-9
- Ciliated protists as indicators of soil health (2021): https://pubblicazioni.unicam.it/retrieve/e0ff0074-f30c-9bac-e053-1705fe0af019/Ciliated%20protists%20as%20indicators%20of%20soil%20health%20%282021%29%20p97-103.pdf
- Soil protozoa as bioindicators (Foissner): https://agris.fao.org/search/fr/records/65df85566eef00c2cea2f91e

**Amoebae**
- Amoebae as bacterial regulators: https://www.doi.org/10.1007/BF00334413
- Protozoa in agricultural soil: https://data.zhenzhi.com/details/1/997534004
- Testate amoebae under farming practices (DOK trial): https://infoscience.epfl.ch/record/177001?ln=en
- Testate amoebae as bioindicators review: https://bibliotekanauki.pl/articles/51996827.pdf

**Nematodes**
- Java paddy nematodes (Biodiversitas 2025): https://garuda.kemdiktisaintek.go.id/documents/detail/6537053
- Mwea, Kenya paddy nematodes: https://rcastoragev2.blob.core.windows.net/d0e8973324b254848883a7ce9f7d4d9d/main.PMC9918771.pdf
- Fertilization and paddy nematodes: https://bohrium.dp.tech/paper/arxiv/5488e26545ce147a86e1808d

**Rotifers**
- Rotifers as trophic sentinels: https://core.ac.uk/outputs/671948169
- Bdelloids in Antarctic soils: https://pmc.ncbi.nlm.nih.gov/articles/PMC3909186

**Algae**
- Desmid trophic indicators, India: https://www.x-mol.com/paper/1428509334409297920
- Desmids and Thai water quality: https://data.zhenzhi.com/details/1/887081341
- Dutch fen desmids: https://natuurtijdschriften.nl/pub/536227
- Wisconsin desmids: https://data.zhenzhi.com/details/1/992514819
- Dinobryon and phosphorus decline: https://pmc.ncbi.nlm.nih.gov/articles/PMC7320944
- Mixotrophs in oligotrophic lakes: https://link.springer.com/article/10.1007/s00442-020-04677-x
- Dinoflagellate key (UNH): https://cfb.unh.edu/phycokey/Choices/Dinophyceae/dino_key.html
- Pinnularia in acidic soils: https://www.jeeng.net/Diatoms-Bacillariophyta-from-the-Genus-Eunotia-and-Pinnularia-developing-on-Soils,126257,0,2.html
- Collodictyon grazing study: https://repository.kulib.kyoto-u.ac.jp/dspace/bitstream/2433/169749/1/s10201-012-0384-6.pdf
