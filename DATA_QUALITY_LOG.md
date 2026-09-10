# Data quality log

Every data quality issue found while analysing
`SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER` (Synthea synthetic
claims: 887M transactions, 124M claims, 1.4M patients), what it would have
cost to miss it, and how it was resolved.

The source is a **read-only Snowflake share**, so nothing could be fixed at
source. Every resolution is a correction layer in
`SYNTHEA_HEALTHCLAIMS.PUBLIC`, a view (`V_CLAIMS_TX_CLEAN`) and a table
(`CODE_DICTIONARY`), defined in [`sql/ddl/`](sql/ddl/).

Issues are ordered by how much damage they do if missed, not by when they were
found. The last section covers **bugs in my own analysis**, which were roughly
as numerous as the ones in the data.

---

## Tier 1: silent wrong answers

These return plausible, confident, wrong numbers. No error, no null, no
warning. They are the reason a curated layer exists at all.

### 1.1 `OUTSTANDING` is a running balance, not accounts receivable

| | |
|---|---|
| **Symptom** | `SUM(OUTSTANDING)` returns **$45,314,446,541**: reads as a catastrophic unpaid balance |
| **Reality** | Genuinely uncollected revenue is **$83,363.50** |
| **Error factor** | ~543,000× |
| **How found** | Cross-checking the A/R figure against per-claim billed-minus-paid, which came to ~$0. The two answers disagreed by five orders of magnitude. |

`OUTSTANDING` is stamped on *every* transaction row as money moves through
CHARGE → TRANSFEROUT → TRANSFERIN → PAYMENT. A single claim contributes a
non-zero value at each intermediate step even though it settles to zero.
Summing all rows counts the same balance repeatedly at every stage of its life.

**Resolution.** Exposed in the view as `OUTSTANDING_RUNNING_BALANCE`. The
column was deliberately *renamed rather than dropped*: hiding it would push
anyone who needs terminal A/R back to the raw table with no warning attached,
whereas a name that says "running balance" makes `SUM()` self-evidently wrong
at the point of writing it.

**Correct measure.** The balance on each claim's chronologically last
transaction:

```sql
ROW_NUMBER() OVER (PARTITION BY CLAIM_ID ORDER BY FROMDATE DESC, CLAIMS_TX_ID DESC) = 1
```

### 1.2 `AMOUNT` is populated on transfer rows, not just charges

| | |
|---|---|
| **Symptom** | `SUM(AMOUNT)` inflates total spend by **$23.4B (~17%)** |
| **How found** | A `TYPE` × `TRANSFERTYPE` × `METHOD` breakdown showed `AMOUNT` non-null on 121.8M `TRANSFERIN` rows |

Transfers move an existing balance between parties; they do not create new
money. Summing `AMOUNT` across all row types counts the same dollar once as a
charge and again each time it is transferred.

**Resolution.** `BILLED_AMOUNT = IFF(TYPE = 'CHARGE', AMOUNT, 0)` in the view.
Summing it cannot double-count.

**Note.** The original project brief asserted "`AMOUNT` only exists on CHARGE
rows." That was wrong: restricting to CHARGE is correct, but for a different
reason than stated.

### 1.3 `PAYER_ID` records who was *billed*, not who *paid*

| | |
|---|---|
| **Symptom** | Attributes **$20.3B** of patient out-of-pocket payments to insurers |
| **How found** | Tracing a single claim through the transfer chain: responsibility shifted to the patient, who then paid directly |

**Resolution.** `METHOD` on PAYMENT rows identifies the payment channel:
`ECHECK` is the insurer's ($129.5B), while `CASH` / `CHECK` / `CC` / `COPAY`
are the patient paying directly ($31.4B). Pre-computed in the view as
`PAID_BY_PAYER` and `PAID_BY_PATIENT`.

This single distinction is what makes the project's headline finding possible
(patients bear 41.6% on wellness visits vs 8.6% on inpatient stays). Without
it, that analysis cannot be done at all.

### 1.4 `DIAGNOSIS1` is mostly *not* a diagnosis

| | |
|---|---|
| **Symptom** | A "top conditions by cost" ranking returned `Full-time employment`, `Medication review due`, and six unlabelled codes in its top 12 |
| **Measured** | Only **46.7%** of claims carry a real condition in position 1. **18.4%** of its uses are procedure codes; **23.7%** of spend sits on non-clinical codes |

Testing against the encounter record explained why: on a 1% sample, **50.6%**
of `DIAGNOSIS1` values are copied from `ENCOUNTERS.REASONCODE` and **13.9%**
from `ENCOUNTERS.CODE`. About two-thirds is encounter metadata, not an illness.

The convention is also **inverted**: `DIAGNOSIS2`–`8` contain zero procedure
codes and get progressively cleaner (59.8% → 98% conditions). The primary
position is the dirtiest one.

**Resolution, two parts.**

1. `CODE_DICTIONARY.IS_CONDITION` separates real diagnoses from visit types,
   procedures, paperwork and social determinants.
2. A **DIAGNOSIS2 fallback**: use `DIAGNOSIS1` when it is a condition,
   otherwise `DIAGNOSIS2`. Recovers **5,939,894 claims** whose only real
   diagnosis sits in position 2; coverage 46.7% → 55.4%.

Both cuts are kept on disk, `condition_cost_clean.sql` (position 1 only,
conservative) and `condition_cost_with_fallback.sql`, because the fallback
attributes a claim's full cost to a nominally *secondary* diagnosis, which is
a real trade-off rather than a strict improvement.

### 1.5 `PROCEDURECODE` mixes three code systems

| | |
|---|---|
| **Symptom** | "Top 3 procedures of 2020" returned two SNOMED *encounter* codes |
| **Also** | 402 codes / **$5.72B** would not resolve against any procedure dictionary |

**Resolution.** `CODE_DICTIONARY` unions code/description pairs from 11
sources across 9 tables. `PROCEDURECODE` now resolves **100%**: 92.0% genuine
procedures, 7.1% drug codes billed as lines, 0.9% encounter types.

---

## Tier 2: wrong scope or grain

Not silently wrong, but wrong if you assume the obvious.

### 2.1 The table spans 1914–2024

110 years of simulated history. Unfiltered totals ($159B) are not business
figures. **Resolution:** a 2020–2024 window baked into the view, so
out-of-scope rows are unreachable rather than merely discouraged.

### 2.2 Volume steps up ~8× in November 2019

| Period | Rows/month | Billed/month |
|---|---|---|
| Jan 2018 – Sep 2019 | ~1.9M | ~$200M |
| Oct 2019 | 2.9M | $356M |
| **Nov 2019 onward** | **~9M** | **~$1.7B** |

Found by charting monthly volume after calendar-2019 looked anomalous in a
year-over-year cut. Calendar-2019 blends two population regimes and is not
comparable to 2020+. **Resolution:** the window starts 2020-01-01, excluding
it deliberately. `sql/results/monthly_volume_2018_2020.csv` retains the
evidence.

### 2.3 Data ends 2024-11-09

2024 totals run ~10–15% light; a raw plot shows a collapse that is a data
boundary. **Resolution:** `q0_spend_trends_by_quarter.sql` emits an `Is Partial` flag on
Q4 2024 so charts can dash or drop it, and indexes series to Q1 2020 = 100.

### 2.4 `PAYERS` has 120 rows for 10 insurers

`PAYER_ID` keys an insurer–*city* pair (10 insurers × 12 simulated cities).
Grouping by it fragments Medicare into twelve pieces.

**This is a grain trap, not corrupt data**: each row carries genuine per-city
figures (Cleveland Medicare 128,452 customers vs Salt Lake City 5,404). An
earlier draft of this log wrongly listed it as a defect.

**Resolution.** The view exposes `PAYER_NAME` (the insurer) *and* `PAYER_CITY`
(the region). An initial version collapsed to name only, which silently
destroyed a usable dimension; the city column was added back once that was
noticed.

### 2.5 Claim counts are not additive across procedure rows

Summing a "number of claims" column across procedure rows gives 249.0M against
124.1M actual claims: exactly **2.0×**, because the average claim carries two
procedures and is counted under each. **Resolution:** documented in
`sql/results/README.md`; correct within a row, never summed across rows.

---

## Tier 3: dead and constant columns

Visible on inspection, so low risk, but they waste analysis time.

| Table | Columns | Issue |
|---|---|---|
| `PAYERS` | ADDRESS, CITY, STATE_HEADQUARTERED, ZIP, PHONE | 100% null (all 120 rows) |
| `CLAIMS` | REFERRING_PROVIDER_ID, OUTSTANDING1, OUTSTANDING2, OUTSTANDINGP | 100% null |
| `CLAIMS_TX` | MODIFIER1, MODIFIER2, LINENOTE | 100% null |
| `CLAIMS_TX` | ADJUSTMENTS (always 0), UNITS (always 1), FEESCHEDULEID (always 1), DIAGNOSISREF1–4 (each a fixed constant) | zero variance |
| `PROVIDERS` | SPECIALITY (1 distinct value), PROCEDURES (always 0) | zero variance |
| `PROVIDERS` | ZIP | corrupt, stored as NUMBER, max 981,172,207 |
| `PATIENTS` | PASSPORT | distinct count (1.12M) exceeds non-null rows, uniqueness assumption unsafe |
| `CLAIMS_TX` |: | 4 stray rows with blank `TRANSFERTYPE`, $647 total |

**Resolution.** The 12 fully-null and 7 constant `CLAIMS_TX`/`CLAIMS` columns
are simply not projected by the view. Found by a full-column profile pass
(`sql/results/profile_*.csv`): null rate, distinct count, min/max/avg per
column, 1% sample on the four largest tables.

---

## Tier 4: structural limits of synthetic data

Not defects. Properties of how Synthea generates data that **invalidate whole
categories of analysis**. Naming them is more useful than working around them.

### 4.1 Collection is 100%: no denials, write-offs or bad debt

Total charges ($160.86B all-time) equal total payments. `ADJUSTMENTS` is 0 on
every one of 887M rows. **Any reimbursement-gap or bad-debt analysis returns
zero by construction.** Verified across 9,054 procedure × payer combinations:
net gap **−$1,392**, with 13 non-zero rows whose maximum is $408 of rounding.

### 4.2 Payment is same-day: no A/R aging

**98.66%** of claims are paid the day they are charged; median 0 days, p99 1
day. Days-in-A/R is not modelled.

The 1.3% tail is not payment lag either: elapsed time tracks *encounter
duration* almost exactly (ratio 0.88–1.07 across every class) and concentrates
in skilled nursing (99.5% of its claims) and hospice (94.1%): inherently
multi-week stays. The claim stays open while charges accumulate; each charge is
still settled immediately.

### 4.3 Patient cost concentration is flatter than reality

Top 1% of patients account for **11.8%** of spend, against a real-world US
claims benchmark of 20–25%. Synthea generates patients independently from
disease-progression models, so it under-produces catastrophic multi-morbidity
cases. Reported as a property of the data, not a finding about healthcare.

### 4.4 Unit prices are not realistic

Allergy immunotherapy bills **$11,122 per injection** against a real-world
$50–200. Attribution and volume are correct; the price is a generator artifact.
Rankings hold; absolute magnitudes do not.

### 4.5 Hospital spend rankings track simulated city size

9 of the top 10 hospitals by total spend are in Cleveland, the most heavily
populated simulated city, not a clinical fact. **Resolution:** report hospital
**cost per patient** instead, which normalises away population size and
survives the artifact ($4,401–$144,422 across 731 sites with ≥1,000 patients).

### 4.6 Code systems use incompatible types

`OBSERVATIONS.CODE` is TEXT (LOINC, e.g. `8302-2`); `MODALITY_CODE` and
`SOP_CODE` are TEXT (DICOM). Every code field being resolved
(`DIAGNOSIS1`–`8`, `PROCEDURECODE`) is NUMBER, so these can never match and
were correctly excluded from the dictionary. Checking `INFORMATION_SCHEMA`
first avoided both a type-mismatch failure and a wasted scan of a 763M-row
table.

---

## Bugs in my own analysis

Found by verification rather than by luck. Roughly as numerous as the source
data issues, which is the honest ratio on work of this size.

| # | Bug | How caught | Fix |
|---|---|---|---|
| 1 | `.REASON` checked before concrete tables, so `Total knee replacement` classified as a **Condition** | Spot-checking 10 sample classifications | Reordered precedence: a table naming the thing beats a `.REASON` citation |
| 2 | `LIKE '%PROCEDURES%'` also matches inside `'PROCEDURES.REASON'` | Same check; the ordering was unreliable in both directions | Exact token match: `', ' \|\| SOURCE_TABLES \|\| ', ' LIKE '%, PROCEDURES, %'` |
| 3 | `MEDICATIONS.REASON` mapped to "Medication or vaccine", backwards | Caught while writing the plan, before execution | `.REASON` columns hold the *diagnosis*, not the drug |
| 4 | `ALLERGIES` omitted from the provenance chain, 6 drug allergens fell to `Other`, `Soy bean` became a Condition | Auditing all 284 provenance-classified rows | Added an `ALLERGIES` branch ahead of the `.REASON` fallback |
| 5 | Semantic tag `event` mapped to Condition, making `Death in hospital` a treatable condition | Same audit | Remapped; 5 completed-death codes moved to a `Mortality event` category |
| 6 | Unknown semantic tags dead-ended at `Other`. The tag regex also produced a false positive, `Hib (PRP-OMP)` yielded tag `prp-omp` | Three rows left in `Other` after a fix that should have emptied it | Only *recognised* tags use the tag branch; everything else falls through to provenance |
| 7 | Dictionary missed 402 `PROCEDURECODE` codes worth **$5.72B** | Checking coverage of every code field, not just the diagnosis ones | Added `MEDICATIONS.CODE` (RxNorm) and imaging body sites: resolution 94.3% → 100% |
| 8 | Used **$160.86B** as total spend | It is the all-time figure; the analysis window total is $99.83B | Corrected before it reached any output |
| 9 | Presented before/after rankings as a side-by-side table, implying a row-to-row mapping that did not exist | The user read across a row and asked how lung carcinoma became COVID-19 | Re-presented as two separate lists plus an explicit "what was removed" table |

Every classification in `CODE_DICTIONARY` carries a `CLASSIFIED_BY` column
(`semantic_tag` / `provenance` / `manual_override`) precisely so mistakes like
these are traceable and correctable with a one-line `UPDATE` rather than a
rebuild.

---

## Verification

Every fix was checked against an independently established total rather than
assumed:

| Check | Result |
|---|---|
| Payer burden reproduced through the view vs the hand-written query | Matched on all 10 rows **to the cent** ($99,111,300,187.66) |
| Condition results after the 999 → 1,453 code dictionary rebuild | **Byte-identical** across all 1,721 rows, 0 cells differed |
| Every code field resolves against the dictionary | **100%** on `DIAGNOSIS1`–`8` and `PROCEDURECODE` |
| Concentration curves monotonic and terminating at 100% | Pass, all three grains |
| Percentiles show median < mean at every grain (right skew) | Pass, ratios 2.6× to 5.3× |
| Spend totals reconcile across every independent analysis | $99,111,300,187 |

---

## Summary

| Category | Count | Status |
|---|---|---|
| Silent wrong answers (Tier 1) | 5 | Fixed in the curated layer |
| Scope / grain traps (Tier 2) | 5 | Fixed or documented |
| Dead / constant / corrupt columns (Tier 3) | 19 columns | Excluded from the view |
| Structural limits (Tier 4) | 6 | Documented as findings |
| Bugs in my own analysis | 9 | Fixed and logged |

The largest single risk in this dataset is **not** a missing value or a bad
join. It is `SUM(OUTSTANDING)` returning $45.3 billion, a number that looks
like a finding, would survive a code review, and is wrong by a factor of
543,000.
