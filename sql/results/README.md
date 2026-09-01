# Query results

Output CSVs from analysis of the Snowflake share
`SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER`.

**Standing scope:** unless a filename says otherwise, results cover
`FROMDATE` **2020-01-01 to 2024-12-31**. The source table spans 1914–2024, so
unfiltered totals are meaningless as business figures. 2019 is deliberately
excluded — monthly volume steps up ~8x in Nov 2019, so calendar-2019 blends two
population regimes (see `monthly_volume_2018_2020.csv`). Data ends 2024-11-09,
so 2024 totals run ~15% light.

Every query that produced these lives in `../analysis/`, one file per result,
named to match — `q2_pattern_within_payer.sql` produces
`q2_pattern_within_payer_2020_2024.csv`. The older headline files come from
`../snowflake_queries.sql`, `../condition_cost_clean.sql` and
`../condition_cost_with_fallback.sql`. The curated objects they read from are
defined in `../ddl/`.

Every result file has a saved query. `q3_lorenz_points_2020_2024.csv` was the
last exception — written before that rule existed — and was reproduced on
2026-08-29 by `q3_lorenz_points.sql`, whose output matches all 300 points
exactly. The CSV was left untouched.

---

## Headline results

| File | Rows | What it is |
|---|---|---|
| `condition_cost_with_fallback_2020_2024.csv` | 1,721 | **The current answer to "which conditions cost most, and is that concentrated by payer".** One row per condition × payer. $72.69B across 33.6M claims, 185 conditions. Uses the DIAGNOSIS2 fallback (below). |
| `condition_cost_by_payer_2020_2024.csv` | 1,621 | Same question, **conservative version** — reads `DIAGNOSIS1` only, no fallback. $68.17B / 31.1M claims. Use this if you need a defensible floor. |
| `q2_who_pays_2020_2024.csv` | 28 | Who actually pays — the insurer/patient split cut five ways (overall, payer type, payer, type of visit, year). Government absorbs 97–98%, commercial 70%, uninsured 0%. Replaces the earlier `payer_patient_burden_split` file. |
| `q2_burden_by_setting_and_payer_2020_2024.csv` | 30 | Patient share by type of visit × kind of insurance. Shows burden is *inverted* against cost — 41.6% on wellness visits, 8.6% on inpatient stays. Replaces the earlier `patient_share_by_encounterclass` file. |
| `q2_patient_cost_by_care_type_2020_2024.csv` | 15 | **Which types of care patients pay most for.** The 185 conditions grouped into 15 clinical care types, one row each, ordered by the share of the bill patients carry. Shares are *patient paid ÷ total paid*, with who-paid taken from the payment method, not from `PAYER_ID`. Maternity and dental are 64.5% of all patient out-of-pocket; dental is the only group in the top four on both money (2nd) and share (4th). `People affected` is **not additive** across rows — it sums to 3,476,252 against 1,259,375 actual patients, since someone with gingivitis and asthma is counted under both. Charted in `../../dashboard/q2_who_bears_the_cost.html`. |
| `patient_share_by_year_payer.csv` | 60 | Patient share by year × payer. **Contains 2019 rows on purpose** — they are the evidence for excluding 2019. Ignore that row when charting a trend. |

### Two analytical choices baked into the headline file

1. **DIAGNOSIS2 fallback** — `DIAGNOSIS1` is not really a principal diagnosis
   here; ~65% of it is copied from encounter metadata ("Well child visit",
   "Medication review due"). The rule used is: take `DIAGNOSIS1` when it is a
   real condition, else fall back to `DIAGNOSIS2`. Recovers 5.9M claims
   (coverage 46.7% → 55.4%). Caveat: position 2 is nominally a *secondary*
   diagnosis, so charging a claim's full cost to it can overstate that
   condition.
2. **`Stress (finding)` classified as a social determinant**, not a condition
   (user's decision). Removed $1.43B net and dropped it out of the ranking.

---

## Q1 — Where does the money go?

| File | Rows | What it is |
|---|---|---|
| `q1_cost_drivers_2020_2024.csv` | 185 | Total spend decomposed per condition into **people × visits each × cost per visit**, so a condition's rank can be attributed to prevalence, frequency or price. The top 20 are not extreme on any single driver — they are moderately extreme on all three at once. |
| `q1_spend_decomposition_2020_2024.csv` | 185 | Companion to the above: the same 185 conditions with total billed, claims, patients and per-patient cost, used for the ranking itself. |
| `q1_cost_variation_2020_2024.csv` | 80 | How widely cost per patient varies **within** a condition. Establishes that ranking by cost per patient reorders the table completely against ranking by total spend. |
| `q1_hospital_variability_2020_2024.csv` | 118 | Cost per claim spread across hospitals, per condition — mean, median, **P25 and P75**, SD, CV, robust CV, min and max. The quartiles were added on 2026-08-29 because panel 3 of `../../dashboard/where_the_money_goes.html` draws its box between them and they are **not symmetric about the median** (pregnancy: $4,745 and $15,768 against a median of $11,499), so the box cannot be reconstructed from the robust CV alone. The query had always computed them and discarded them before output; all 118 rows and every pre-existing cell are unchanged. |
| `q1_hospital_cost_spread_2020_2024.csv` | 20 | The condensed version — 20 rows summarising the spread that `q3_hospital_cost_intensity` later measures properly across 731 sites. |

## Q2 — Who actually pays?

The five headline Q2 files are in the table at the top. These are the rest.

| File | Rows | What it is |
|---|---|---|
| `q2_who_pays_by_year_2020_2024.csv` | 120 | The who-pays split repeated per year. Every ratio is flat across 2020–2024, which is the evidence that this is benefit design rather than drift. |
| `q2_oop_by_condition_2020_2024.csv` | 183 | Patient out-of-pocket per condition. Largely a restatement of Q1 — the two rankings correlate at 0.971, because out-of-pocket is total billed × patient share. |
| `q2_spend_vs_patient_cost_rank_2020_2024.csv` | 185 | The two rankings side by side, which is what establishes that 0.971. |
| `q2_top10_patient_paid_2020_2024.csv` | 10 | Top 10 conditions by total patient out-of-pocket. |
| `q2_top10_by_share_of_bill_2020_2024.csv` | 10 | Top 10 by **share** of the bill instead of dollars — a different list, and the one that shows share is not constant (0% to 78.8%, median 27.3%). |
| `q2_top10_share_by_payer_type_2020_2024.csv` | 10 | Those same 10 split by insurance type, showing the blended figure hides most of the story. |
| `q2_share_by_payer_type_yearly_2020_2024.csv` | 40 | Patient share by insurance type per year. Flat throughout. |
| `q2_care_type_share_by_payer_type_2020_2024.csv` | 60 | The 15 care types × 4 insurance types. The per-care-type companion to the file above. |
| `q2_concussion_detail_2020_2024.csv` | 11 | Why concussion tops the share-of-bill list at 67.9% — a single-condition drill-down. |
| `q2_commercial_cap_by_care_type_2020_2024.csv` | 15 | **Which care types sit above the point where commercial patients stop paying.** Maternity, allergy and cancer are 94–98% above it; blood disorders and kidney barely reach it (2–6%). Explains why diabetes carries such a high patient share — 80% of it never gets large enough to approach the annual cap. |
| `q2_cap_reversal_diagnosis_2020_2024.csv` | 33 | Investigates the three care types where patients pay **more** of large claims. It is a composition effect, not a cost-sharing one: below $5,000 `Kidney & urinary` is 91% dialysis at $459 a claim, above it 100% bladder infections at $7,620. Different conditions sharing a folder. |
| `q2_pattern_breakers_2020_2024.csv` | 15 | **Why two care types appear to break the cheap-care/high-share rule.** Neither does. `Infections` only looks dear per person (median claim $1,542 against a $5,466 mean); `Brain & nervous system` is 90.2% government-funded, and those patients pay almost nothing. Also carries the payer mix and claim-size columns for all 15 groups. |
| `q2_pattern_within_payer_2020_2024.csv` | 30 | **The test that the cost/share pattern is not an artefact of payer mix.** Each care type twice, once per insurance type. The relationship strengthens inside each group rather than collapsing. `Brain & nervous system` goes from 8.5% blended to 40.2% commercial. Excludes the uninsured, so three care types show a blended share *above* their commercial one — that is the uninsured paying 100%, not a commercial effect. |

## Q3 — How concentrated is spend?

| File | Rows | What it is |
|---|---|---|
| `q3_concentration_2020_2024.csv` | 4 | Charted in `../../dashboard/places_not_people.html` (bars, for stakeholders) and `../../dashboard/concentration.html` (Lorenz curves). Pareto curves at four grains — patients, conditions, organisations, care types. **Read the denominators and entity counts before comparing rows**: patients and organisations cover all $99.11B, conditions and care types only the $72.69B carrying a diagnosis. The condition and care-type rows restate Q1; the answer rests on patients (134,198 for half the spend) versus hospitals (86). |
| `q3_top_entities_2020_2024.csv` | 50 | The named entities behind those curves — the individual top patients, conditions and organisations. |
| `q3_hospital_cost_intensity_2020_2024.csv` | 731 | **Why hospitals differ.** Cost per patient decomposed into visits per patient × cost per visit, for every site with ≥1,000 patients. A 32.8× spread, tracking cost per visit (+0.81) somewhat more closely than visit frequency (+0.65). The extreme tail behaves differently from the broad middle, which is why the recommendation splits by position in the distribution. Charted in `../../dashboard/two_ways_expensive.html`, which separates the three groups the single cost-per-patient figure hides: the ordinary bulk, 12 veterans' sites at ordinary prices with ~50 visits each, and 22 hospices whose "price per visit" is really a price per multi-week stay. |
| `q3_site_group_conditions_2020_2024.csv` | 45 | **What patients are seen for, by kind of site** — the 15 care types, split three ways: veterans' sites, hospice & nursing, everywhere else. Carries the measure that settles the "good access or unresolved problems" question: visits per condition, 6.31 at veterans' sites against 3.42 elsewhere. Conditions per patient barely differ (4.49 vs 4.05), so those patients are not sicker in more ways — they return more often for the same thing. |
| `q3_site_group_top_conditions_2020_2024.csv` | 229 | The same split at **condition** level, which is where the answer actually is. Two thirds of visits to veterans' sites are kidney failure — chronic kidney disease stage 4 at 53.1% of visits and 129 visits per patient, end-stage renal disease at 11.7% and 71.6 — both around $815 a visit. That is dialysis, and it is **neither good nor bad care**: kidney patients elsewhere average 141 visits, slightly *more*. The sites look extreme only because kidney failure is 65% of their work against 31% elsewhere. |
| `q3_hospice_site_encounter_mix_2020_2024.csv` | 5 | **Written to correct a chart that was wrong.** `two_ways_expensive.html` explained the hospice cluster as "one whole stay = one visit", using evidence grouped by `ENCOUNTERCLASS` across all organisations — but the cluster is defined by organisation *name*. Different populations. At those 22 sites only **18.1% of visits are hospice-class** (22.3 days each, 50.7% of the money); **63.9% are ordinary same-day emergency trips** at $2,774. Long stays carry the money and lift the per-visit average; they are not most of the visits. Hospice still bills ~$567 a day, below skilled nursing at $740. |
| `q1_pregnancy_sensitivity_2020_2024.csv` | 2 | **Sensitivity test: does the condition ranking survive correcting pregnancy's 8.6x pricing error?** No, for the ranking; yes, for concentration. Repricing every pregnancy claim down by 8.6x drops it from rank 1 (39.8%) to rank 5 (7.1%); allergy and gingivitis move to 1st and 2nd. Top-5 share of diagnosed spend falls 74.1% -> 60.1%, top-20 falls 90.8% -> 85.8%. Patient-level spend concentration (Finding 4) goes the OTHER way: repricing pregnancy down makes the top 1% of patients carry MORE of total spend (11.8% -> 15.4%), because pregnancy spend was moderate and broadly spread, and removing it shifts weight toward genuinely high-cost patients. |
| `q2_oop_percentiles_by_care_type_2020_2024.csv` | 15 | **The dollar side of Finding 2, not just the percentage side.** For each type of care, the median/P75/P90 amount an AFFECTED member actually paid out of pocket over five years. Reorders the story sharply: blood disorders and diabetes lead on SHARE (38.9%, 36.6%) but have the lowest real dollar exposure among high-share categories (median $179, $233). Maternity, only 4th by share (17.0%), has by far the highest dollar exposure (median $10,765, P90 $64,681). Share and dollar burden are not the same finding. |
| `q2_member_paid_percentiles_2020_2024.csv` | 1 | **The median beside the $16,084 mean.** Per section 6's own rule (median over mean on skewed distributions), applied to the headline patient-paid-per-member figure: mean $16,084, median $7,026, P75 $19,005, P90 $35,478. The typical member paid well under half of the average -- "$16,084 per member" should not be read as what a typical member paid. |
| `q3_preventive_access_2020_2024.csv` | 10 | **Why "do high-spend members skip preventive care" is not answerable here.** Wellness encounters reach **1,259,199 of 1,259,375** patients — 99.99%, with under 0.03% missing in any spend decile, so there is no access gap to measure. Visits per member trace an arch (3.94 → 4.94 → 3.84) that tracks age, not spend: average age climbs to 51 by decile 8 then falls back to 40, because pregnancy is 39.8% of spend and puts younger women at the top. Synthea schedules wellness visits by protocol and models no one declining care. |
| `q3_pregnancy_pathway_split_2020_2024.csv` | 4 | **Why the one variable condition is not a lever either.** Normal pregnancy is the only condition where hospitals differ much (0.962 against a typical 0.027) on $28.9B. Its 856 sites, ranked by cost per claim and cut into four groups of 214, show a **cliff not a slope**: groups 1–2 are delivery units (~1.3 visits, **95.5% and 95.8%** of women giving birth on site, $4,130–$5,263 a claim); groups 3–4 are antenatal clinics (~10 visits, **12.2% and 6.8%**, $13,640–$17,314). Nothing sits between them. Waste would show as a smooth spread; two populations sharing a billing code do not. |
| `q3_utilisation_or_composition_2020_2024.csv` | 119 | **The file that eliminated Q3's last candidate lever.** Spread in procedures per claim between hospitals, per condition. The typical condition is **0.027** — sites do effectively identical amounts of work. Only 12 of 119 exceed 0.5 and all but one are small; the exception is normal pregnancy at 0.962 across 856 sites and $28.9B. Its query header carries the second test, which shows even that is pathway split (cheap sites deliver babies, dear sites run antenatal clinics) rather than practice variation — and records the $17.3B "excess over median" figure as a trap not to be quoted. |
| `q3_price_vs_casemix_2020_2024.csv` | 730 | **The file that withdrew Q3's price recommendation.** Each site's actual cost per visit against what it would cost with every procedure repriced to its all-hospital average. The spread barely moves — 15.8× to 15.2× — and a median of only **7.8%** of a site's cost per visit reflects what it charges rather than what it does. Cost per visit is case-mix intensity wearing a price label, so there is no price variation to negotiate. Resolves a straight contradiction between §Q1 (no negotiated rates, `ADJUSTMENTS` 0 on all 887M rows) and §Q3, in §Q1's favour. |
| `q3_lorenz_points_2020_2024.csv` | 300 | Lorenz curve coordinates — 100 points per grain, the data behind the three curves in `../../dashboard/concentration.html`. Each row: rank the grain most-expensive-first, walk to the Nth percentile, and this much of its spend is covered. The same computation as `q3_concentration`, keeping all 100 steps instead of six milestones. Grains do not share a denominator — patients and organisations are out of $99.11B, conditions out of $72.69B. |

## Trends

| File | Rows | What it is |
|---|---|---|
| `trends_quarterly_2020_2024.csv` | 20 | Spend, claims and patients per quarter. |
| `trends_setting_mix_2020_2024.csv` | 50 | How the mix of care settings shifts over the window. |

---

## Negative findings — questions the data cannot answer

These files exist to document that an analysis returned nothing, which is
itself the finding. Do not re-run them expecting a different answer.

| File | Rows | What it shows |
|---|---|---|
| `procedure_payer_reimbursement_gap_2020_2024.csv` | 8,413 | Billed vs paid per procedure × payer. **The gap is zero everywhere** — $99,111,300,286 billed vs $99,111,301,679 paid, net −$1,392. Only 13 rows have any gap, max $408 (rounding). Collection is 100% by construction: no denials, write-offs or contractual adjustments exist. |
| `revenue_cycle_by_payertype_2020_2024.csv` | 3 | Days-to-payment and terminal balances by payer type. **98.66% of claims are paid the same day**; median 0 days, p99 = 1 day. Uncollected revenue is $83K against $99.8B. Days-in-A/R is not modelled. |
| `terminal_outstanding_2020_2024.csv` | 1 | The trap behind the above. Naive `SUM(OUTSTANDING)` = **$45,314,446,541**, which looks like a catastrophic A/R balance. The sum of each claim's *last* transaction is **$83,363.50**. `OUTSTANDING` is a mid-flow running balance — never report it as uncollected revenue; it overstates by ~543,000x. |
| `delayed_claims_tail_2020_2024.csv` | 22 | Why the 1.3% of claims *not* paid same-day are not evidence of payment lag: elapsed time matches encounter duration almost exactly (ratio 0.88–1.07), concentrated in skilled nursing (99.5% of claims) and hospice (94.1%) — inherently multi-week stays. |

---

## Diagnostics — how the data behaves

| File | Rows | What it shows |
|---|---|---|
| `claims_tx_money_flow.csv` | 12 | **The decoder ring for `CLAIMS_TX`.** One row per `TYPE` × `TRANSFERTYPE` × `METHOD`. Establishes that `AMOUNT` is populated on `TRANSFERIN` rows as well as `CHARGE` (so naive sums double-count $23.4B), and that `METHOD` on PAYMENT rows reveals who actually paid — `ECHECK` = insurer, `CASH`/`CHECK`/`CC`/`COPAY` = patient. **Unfiltered / all-time**, so its $160.9B will not tie to the windowed files. |
| `monthly_volume_2018_2020.csv` | 36 | Row counts and charges per month, 2018–2020. Located the Nov 2019 step-change: ~$200M/month through Sep 2019, then ~$1.7B/month onward. The reason 2019 is excluded from the standing window. **Starts 2018 on purpose.** |
| `q1_pregnancy_procedures_2020_2024.csv` | 86 | **The evidence that prices are not realistic.** Every line item billed on claims attributed to Normal pregnancy. Four routine checks carry 68.3% of the condition's $28.9B — a fundal-height measurement and a fetal-heart auscultation at ~$4,967 each, billed 1.6M times apiece. Price those four as bundled and pregnancy falls to $9.2B. |
| `q1_allergy_procedures_2020_2024.csv` | 18 | Same query, Allergy to substance. The cleaner demonstration: **subcutaneous immunotherapy is 98.5% of the condition at $11,122 a shot** (real-world $50–200) while the encounter containing it is priced correctly at $118. Synthea prices encounters realistically and procedures at a flat few thousand regardless of what they are. |
| `dictionary_provenance_rows.csv` | 284 | Audit trail for the code dictionary — every code classified by *provenance* (which source table it appears in) rather than by its SNOMED semantic tag. This is the weakest-evidence group; the `REASON_ONLY` column flags the weakest rows within it. |

---

## Column profiles

Per-column stats for each source table: null count and rate, approximate
distinct count, min/max/avg for numerics, string lengths for text.
Produced by the `/explore-data` pass.

| File | Columns profiled | Note |
|---|---|---|
| `profile_claims_tx.csv` | 33 | 1% sample — figures are estimates |
| `profile_claims.csv` | 32 | 1% sample |
| `profile_patients.csv` | 29 | full scan |
| `profile_payers.csv` | 22 | full scan |
| `profile_encounters.csv` | 16 | 1% sample |
| `profile_providers.csv` | 14 | full scan |
| `profile_conditions.csv` | 9 | 1% sample |

The four large tables (CLAIMS_TX 887M, CLAIMS 124M, ENCOUNTERS 64M,
CONDITIONS 38M rows) were profiled from a 1% `SAMPLE` to cap cost. Row counts
are exact (from `SHOW TABLES`); null rates and distinct counts are estimates.

## Cost summaries

| File | Rows | What it is |
|---|---|---|
| `cost_percentiles_2020_2024.csv` | 3 | **What a typical claim, visit and patient costs.** Full percentile spread at three grains. Cost is right-skewed everywhere — a claim's mean is 5.28x its median ($1,454 vs $276) — so **never quote a mean here without its median**. The skew falls as the grain widens (5.28x per claim, 2.93x per visit, 2.62x per patient). Percentiles are `APPROX_PERCENTILE`, so approximate; counts and totals are exact. Column headers are raw SQL names, predating the naming rule in §21. |
| `procedure_base_cost_summary.csv` | 545 | min/max/avg `BASE_COST` per procedure description. |
| `encounter_cost_summary.csv` | 10 | min/max/avg total claim cost, payer coverage and base cost per encounter class. Inpatient averages ~$29K/encounter vs ~$2.6K ambulatory. |

`procedure_base_cost_summary` and `encounter_cost_summary` are **not**
date-windowed — both are all-time. `cost_percentiles_2020_2024` is windowed
like everything else, and reconciles to the $99,825,019,809 all-spend
reference at all three grains.

---

## Known limitations

- **The data models 100% collection.** No denials, write-offs, bad debt or
  A/R aging exist. Any analysis of those returns zero by construction, not
  because performance is perfect.
- **`DIAGNOSIS1` mixes code systems.** 18.4% of its uses are procedure codes;
  only `DIAGNOSIS1` contains them (positions 2–8 have none). 23.7% of spend
  sits on non-clinical codes including employment status.
- **Condition classification involves judgment.** 25 codes were classified by
  hand; the rest by SNOMED semantic tag (690) or provenance (284). The
  `CLASSIFIED_BY` column in `CODE_DICTIONARY` records which, so any row can be
  traced and overridden with a one-line `UPDATE`.
- **Claim counts are not additive across rows** in the procedure files — a
  claim carrying two procedures is counted once under each (2.0x inflation
  against the 124M actual claims).
