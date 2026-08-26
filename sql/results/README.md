# Query results

Output CSVs from analysis of the Snowflake share
`SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER`.

**Standing scope:** unless a filename says otherwise, results cover
`FROMDATE` **2020-01-01 to 2024-12-31**. The source table spans 1914–2024, so
unfiltered totals are meaningless as business figures. 2019 is deliberately
excluded — monthly volume steps up ~8x in Nov 2019, so calendar-2019 blends two
population regimes (see `monthly_volume_2018_2020.csv`). Data ends 2024-11-09,
so 2024 totals run ~15% light.

Every query that produced these lives in `../snowflake_queries.sql`,
`../condition_cost_clean.sql` or `../condition_cost_with_fallback.sql`.
The curated objects they read from are defined in `../ddl/`.

---

## Headline results

| File | Rows | What it is |
|---|---|---|
| `condition_cost_with_fallback_2020_2024.csv` | 1,721 | **The current answer to "which conditions cost most, and is that concentrated by payer".** One row per condition × payer. $72.69B across 33.6M claims, 185 conditions. Uses the DIAGNOSIS2 fallback (below). |
| `condition_cost_by_payer_2020_2024.csv` | 1,621 | Same question, **conservative version** — reads `DIAGNOSIS1` only, no fallback. $68.17B / 31.1M claims. Use this if you need a defensible floor. |
| `q2_who_pays_2020_2024.csv` | 28 | Who actually pays — the insurer/patient split cut five ways (overall, payer type, payer, type of visit, year). Government absorbs 97–98%, commercial 70%, uninsured 0%. Replaces the earlier `payer_patient_burden_split` file. |
| `q2_burden_by_setting_and_payer_2020_2024.csv` | 30 | Patient share by type of visit × kind of insurance. Shows burden is *inverted* against cost — 41.6% on wellness visits, 8.6% on inpatient stays. Replaces the earlier `patient_share_by_encounterclass` file. |
| `q2_patient_cost_by_care_type_2020_2024.csv` | 16 | **Which types of care patients pay most for.** The 185 conditions grouped into 16 clinical care types, one row each, ordered by the share of the bill patients carry. Maternity and dental are 64.5% of all patient out-of-pocket; preventive dental is the only group in the top three on both money (2nd) and share (3rd). `People affected` is **not additive** across rows — it sums to 3,752,982 against 1,259,375 actual patients, since someone with gingivitis and asthma is counted under both. |
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
