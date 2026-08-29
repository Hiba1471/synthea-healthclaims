# Data Analysis Context & Constraints

## Purpose

This file defines the working rules, quality standards, and constraints for all data analysis performed in this project.

**Sections 1–23 are general rules** that apply to any dataset.
**Sections 24–27 are specific to this project** — the dataset, its curated
layer, its known traps, and the questions answered so far. Read 24–26 before
writing a query against this data; several of the traps produce confident,
plausible, wrong answers rather than errors.

The goal is to produce analysis that is:

- Accurate
- Reproducible
- Traceable
- Easy to review
- Conservative about assumptions
- Clear about uncertainty
- Useful for decision-making

---

## 1. General Analysis Rules

1. Never invent, estimate, or fabricate data unless explicitly asked to create synthetic data.
2. Use the provided dataset as the primary source of truth.
3. Do not silently modify source data.
4. Preserve the original dataset whenever possible and perform transformations on a copy.
5. Clearly distinguish:
   - Raw values
   - Cleaned values
   - Derived values
   - Assumptions
   - Estimates
6. If required information is missing, state what is missing instead of guessing.
7. If a conclusion cannot be supported by the available data, explicitly say so.
8. Prefer correctness and transparency over producing a confident-looking result.

---

## 2. Data Validation

Before performing substantive analysis:

- Inspect dataset shape and dimensions.
- Review column names and data types.
- Identify duplicate records.
- Identify missing/null values.
- Identify unexpected values or categories.
- Check numerical ranges for implausible values.
- Check dates for invalid or inconsistent formats.
- Check identifier fields for uniqueness where uniqueness is expected.
- Look for inconsistent capitalization, spelling, whitespace, and formatting.
- Check for units and confirm that comparable fields use compatible units.

Do not automatically remove suspicious records.

Instead:

1. Identify the issue.
2. Explain why the record may be problematic.
3. Apply a cleaning rule only when justified.
4. Record the rule used.

---

## 3. Missing Data

Never automatically convert missing values to zero.

Treat these as potentially different concepts:

- `0`
- blank string
- `NULL`
- `NaN`
- unavailable
- unknown
- not applicable

Before imputing missing values:

- Explain the proposed method.
- Explain why the method is appropriate.
- Report how many observations are affected.

If imputation is not necessary, prefer retaining missing values.

---

## 4. Duplicate Data

Do not remove duplicates solely because two rows look similar.

Confirm whether duplication means:

- True duplicate record
- Multiple valid transactions
- Multiple events for the same entity
- Repeated measurement
- Version/history records

When duplicates are removed, report:

- Number of rows removed
- Columns or rules used to identify duplicates
- Reason the removal was justified

---

## 5. Calculations

All reported calculations should be reproducible.

For important metrics:

- Use explicit formulas.
- Verify calculations programmatically where possible.
- Avoid manual arithmetic for large or important calculations.
- Keep full numerical precision during calculations.
- Round only for presentation unless the methodology requires otherwise.

For percentages, clearly identify the denominator.

For percentage change, use:

`(new_value - old_value) / old_value * 100`

Do not confuse:

- Percentage change
- Percentage-point change
- Share of total
- Growth rate

---

## 6. Aggregations

Before aggregating:

- Confirm the intended grain of the dataset.
- Identify the grouping fields.
- Check whether one entity can appear multiple times.
- Avoid double counting caused by joins or one-to-many relationships.

For totals, counts, averages, or ratios, state what is being aggregated.

Prefer meaningful metrics over unnecessary aggregation.

Examples:

- Use median when distributions are strongly skewed.
- Report counts alongside percentages when useful.
- Use weighted averages when observations have different weights.

---

## 7. Joins and Merges

Before joining datasets:

- Identify expected join cardinality:
  - one-to-one
  - one-to-many
  - many-to-one
  - many-to-many
- Check key uniqueness.
- Check unmatched records.
- Check whether row counts unexpectedly increase after the join.

Never allow a many-to-many merge to inflate results without explicitly identifying and justifying it.

After important joins, validate:

- Row count before and after
- Number of matched records
- Number of unmatched records
- Duplicate key behavior

---

## 8. Date and Time Analysis

Always verify:

- Date parsing
- Time zone
- Date range
- Frequency/granularity
- Missing dates
- Duplicate timestamps

Do not treat partial periods as complete periods without clearly labeling them.

For month-over-month or year-over-year comparisons:

- Compare equivalent periods.
- Mention incomplete periods.
- Avoid comparing partial current periods with full historical periods unless specifically required.

---

## 9. Statistical Analysis

Do not imply causation from correlation alone.

When using statistical tests:

- State the hypothesis.
- State the test used.
- Explain why it is appropriate.
- Report relevant statistics and sample size.
- Report uncertainty where appropriate.
- Note important assumptions.

For model evaluation:

- Keep training and test data separate.
- Avoid data leakage.
- Use appropriate baselines.
- Prefer cross-validation when appropriate.
- Report metrics relevant to the business problem.

Do not select a metric solely because it makes the model appear better.

---

## 10. Outliers

Do not automatically delete outliers.

First determine whether an outlier is:

- A data-entry error
- A measurement error
- A legitimate rare observation
- A meaningful business event

If outliers are excluded or winsorized:

- State the rule.
- Report how many records were affected.
- Compare results with and without the treatment when material.

---

## 11. Visualization Constraints

Every chart should communicate a specific point.

Charts should:

- Have a descriptive title.
- Label axes clearly.
- Include units.
- Use readable scales.
- Avoid misleading axis truncation.
- Avoid unnecessary visual effects.
- Avoid 3D charts unless explicitly requested.
- Use consistent category ordering where applicable.
- Use chronological ordering for time-series data.

Prefer:

- Bar charts for category comparisons
- Line charts for trends over time
- Scatter plots for relationships
- Histograms for distributions
- Box plots for distribution comparisons

Do not use pie charts when many categories make comparison difficult.

The visualization must agree exactly with the underlying calculated values.

---

## 12. Reporting Results

Structure findings so that a reviewer can distinguish:

### Observation
What the data directly shows.

### Interpretation
What the observation may mean.

### Recommendation
What action could reasonably follow.

Do not present interpretations as facts.

Highlight:

- Key findings
- Material exceptions
- Important trends
- Risks
- Data limitations
- Uncertainty
- Recommended next steps

Avoid overstating small or statistically insignificant differences.

---

## 13. Business Metrics

Before calculating a business KPI, define it explicitly.

Examples:

### Conversion Rate

`converted_entities / eligible_entities`

### Retention Rate

Define:

- Cohort
- Start period
- Retention period
- What counts as retained

### Revenue Growth

Specify whether the comparison is:

- Month-over-month
- Quarter-over-quarter
- Year-over-year

### Average

Clarify whether it means:

- Mean
- Median
- Weighted mean

Never assume that a business term has only one definition.

---

## 14. Data Leakage and Future Information

For predictive analysis, never use information that would not have been available at prediction time.

Examples of leakage include:

- Future outcomes
- Post-event status fields
- Finalized labels
- Future transactions
- Aggregations containing future periods

Use time-aware train/test splits where chronological ordering matters.

---

## 15. Privacy and Sensitive Data

Minimize exposure of personally identifiable or sensitive information.

Do not include unnecessary:

- Names
- Emails
- Phone numbers
- Addresses
- Account identifiers
- Personal identifiers

Use aggregated or anonymized values whenever the identity of individual records is not necessary.

---

## 16. Reproducibility

Analysis should be reproducible from the original input.

Where applicable:

- Use deterministic transformations.
- Set random seeds for randomized processes.
- Keep transformations in logical sequence.
- Do not manually alter intermediate results.
- Document important assumptions.
- Keep calculated fields traceable to source columns.

Prefer code-based transformations over undocumented spreadsheet edits.

---

## 17. Python Analysis Preferences

When Python is used:

- Prefer `pandas` for tabular analysis.
- Prefer `numpy` for numerical operations.
- Prefer `matplotlib` for charts unless another library is specifically required.
- Use descriptive variable names.
- Avoid unnecessary loops when vectorized operations are clearer.
- Do not suppress warnings without understanding them.
- Validate intermediate outputs for important transformations.

For large datasets:

- Avoid unnecessary full copies.
- Read only required columns when practical.
- Use appropriate data types.
- Consider chunked processing when memory is constrained.

---

## 18. SQL Analysis Constraints

When SQL is used:

- Never assume row uniqueness.
- Validate join cardinality.
- Avoid `SELECT *` in final analytical queries when specific columns are known.
- Use explicit aliases.
- Make filtering conditions visible.
- Be careful with `NULL` behavior.
- Avoid accidental integer division.
- Verify date boundaries.
- Validate aggregates against base-record counts.

Use CTEs when they materially improve readability.

---

## 19. Excel / Spreadsheet Analysis Constraints

When working with spreadsheets:

- Preserve original input sheets when possible.
- Clearly separate raw data, calculations, and outputs.
- Avoid hard-coded values inside formulas when a reference cell is more appropriate.
- Use formulas for derived values rather than manually entering calculated numbers.
- Ensure formula ranges cover the full intended dataset.
- Avoid merged cells inside analytical data tables.
- Use consistent date and number formats.
- Make assumptions visible in dedicated cells or notes.

---

## 20. Quality Checks Before Finalizing

Before reporting final results, verify:

- [ ] Source data was not unintentionally modified
- [ ] Dataset dimensions were inspected
- [ ] Missing values were reviewed
- [ ] Duplicates were reviewed
- [ ] Data types were checked
- [ ] Important formulas were validated
- [ ] Aggregations do not double count
- [ ] Joins did not unexpectedly multiply records
- [ ] Percentages use the correct denominator
- [ ] Dates and periods are comparable
- [ ] Outlier treatment is documented
- [ ] Charts match calculated values
- [ ] Conclusions are supported by evidence
- [ ] Assumptions are explicitly stated
- [ ] Limitations are reported
- [ ] Final figures have been independently sanity-checked

---

## 21. Communication Style

**Column names must make sense to a non-specialist.** Tables, chart axes,
legends and CSV headers are read by people without healthcare, insurance or
finance background. Name the column so it needs no explanation:

| Instead of | Write |
|---|---|
| OOP | Patient Out of Pocket |
| Payer coverage | Insurer Covers |
| Cost-sharing ratio | % of Bill Patient Pays |
| Severity-filtered (>=90% inpatient) | Counted only for hospitalised patients |
| CV / IQR ratio | Variation (gap between cheapest and dearest quarter of hospitals) |

Fix the *name*; do not append a definition to every column, which bloats the
output. Gloss a genuinely unavoidable term once, in the subtitle or a
footnote.


Present analysis in clear, straightforward language.

Prefer this structure:

1. Executive summary
2. Key metrics
3. Important findings
4. Supporting analysis
5. Limitations
6. Recommendations

Use tables when they improve comparison.

Avoid unnecessary technical terminology in business-facing summaries.

When technical terminology is necessary, explain it briefly.

---

## 22. Uncertainty Rule

When uncertain, do not hide the uncertainty.

Use language such as:

- "The available data suggests..."
- "This cannot be determined from the current dataset."
- "This result depends on the assumption that..."
- "The dataset does not contain enough information to verify..."
- "This appears to be..., but should be validated against..."

Never manufacture certainty to complete an analysis.

---

## 23. Final Principle

A correct analysis with clearly stated limitations is preferable to a polished analysis built on unsupported assumptions.

Every important result should be traceable back to:

**Source Data → Transformation → Calculation → Result → Interpretation**

---

# PROJECT-SPECIFIC CONTEXT

Everything below applies to the Synthea healthcare claims project only.

---

## 24. Dataset and Environment

### Source

**`SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER`** — a Snowflake
share of Synthea-generated synthetic healthcare data. 18 tables, ~2.3B rows.

The share is **read-only**. It cannot be altered, so all corrections live in a
curated layer rather than being fixed at source. This satisfies §1 rule 3–4
(do not modify source data) by construction.

### Curated layer — query these, not the raw tables

**`SYNTHEA_HEALTHCLAIMS.PUBLIC`**

| Object | Type | Purpose |
|---|---|---|
| `V_CLAIMS_TX_CLEAN` | view | Claim transactions with corrected money columns, payer collapsed, date window applied |
| `CODE_DICTIONARY` | table, 1,453 rows | Every clinical code → one canonical name + category. 100% resolution on all 9 code fields |

DDL: `sql/ddl/`. Run order: `v_claims_tx_clean.sql` →
`code_dictionary_raw.sql` → `code_dictionary_classify.sql`.

### Standing analysis window

**`FROMDATE >= '2020-01-01' AND FROMDATE < '2025-01-01'`**, baked into the view.

- Unfiltered, the data spans **1914–2024** (~110 years). Cumulative totals are
  not business figures.
- Volume steps up **~8×** at Nov 2019 (~$200M → ~$1.7B/month), so calendar-2019
  blends two population regimes and is excluded deliberately.
- Data ends **2024-11-09**, so 2024 totals run ~10–15% light. Per §8, label
  partial periods; never plot raw Q4 2024 as a decline.

### Reference totals — every analysis must reconcile to one of these

| Figure | Value |
|---|---|
| All spend, 2020–2024 | **$99,825,019,809** |
| Excluding admin noise code 185347001 | **$99,111,300,187** |
| Attributable to a clinical condition | **$72,685,492,693** |
| Patients with spend | **1,259,375** |
| Claims | **68,645,121** |

A new number that does not tie to one of these is a bug until proven otherwise.

---

## 25. Data Dictionary

### Tables used

| Table | Rows | Grain | Key columns used |
|---|---|---|---|
| `CLAIMS_TX` | 886,973,449 | one billing **line item** | `CLAIMS_TX_ID`, `CLAIM_ID`, `ENCOUNTER_ID`, `PATIENT_ID`, `TYPE`, `AMOUNT`, `PAYMENTS`, `METHOD`, `TRANSFERTYPE`, `PROCEDURECODE`, `FROMDATE`, `OUTSTANDING` |
| `CLAIMS` | 124,140,497 | one **claim** | `CLAIM_ID`, `PATIENT_ID`, `ENCOUNTER_ID`, `DIAGNOSIS1`–`DIAGNOSIS8`, `SERVICEDATE` |
| `ENCOUNTERS` | 64,535,917 | one **visit** | `ENCOUNTER_ID`, `PATIENT_ID`, `ORGANIZATION_ID`, `PAYER_ID`, `ENCOUNTERCLASS`, `CODE`, `REASONCODE`, `TOTAL_CLAIM_COST` |
| `PATIENTS` | 1,421,656 | one **person** | `PATIENT_ID`, `BIRTHDATE`, `DEATHDATE`, `RACE`, `GENDER`, `INCOME` |
| `PAYERS` | 120 | one insurer **× city** (10 × 12) | `PAYER_ID`, `NAME`, `SYNTHEA_CITY` |
| `ORGANIZATIONS` | 4,034 | one **care site** | `ORGANIZATION_ID`, `NAME`, `CITY`, `STATE` |
| `PROVIDERS` | 4,034 | one **clinician** | `PROVIDER_ID`, `ORGANIZATION_ID` |
| `CONDITIONS` | 38,493,229 | one patient **diagnosis** | `CODE`, `DESCRIPTION`, `PATIENT_ID`, `ENCOUNTER_ID` |
| `PROCEDURES` | 148,523,805 | one **procedure** | `CODE`, `DESCRIPTION`, `BASE_COST`, `REASONCODE` |
| `MEDICATIONS` | 59,604,585 | one **prescription** | `CODE` (RxNorm), `DESCRIPTION`, `REASONCODE` |
| `IMMUNIZATIONS` | 11,499,779 | one **vaccination** | `CODE`, `DESCRIPTION` |
| `ALLERGIES` | 1,308,603 | one **allergy** | `CODE`, `DESCRIPTION` |
| `DEVICES` | 5,694,041 | one **device** | `CODE`, `DESCRIPTION` |
| `SUPPLIES` | 25,169,946 | one **supply** | `CODE`, `DESCRIPTION` |
| `CARE_PLANS` | 3,961,944 | one **care plan** | `CODE`, `DESCRIPTION`, `REASONCODE` |

**Not used:** `OBSERVATIONS` (763M rows, LOINC codes stored as TEXT — cannot
join to the numeric code fields), `IMAGING_STUDIES` (DICOM), `PAYER_TRANSITIONS`.

### `V_CLAIMS_TX_CLEAN` — column reference

Grain unchanged: **one row per `CLAIMS_TX` line item**, filtered to 2020–2024.

| Column | Notes |
|---|---|
| `CLAIMS_TX_ID`, `CLAIM_ID`, `ENCOUNTER_ID`, `PATIENT_ID` | keys |
| `FROMDATE`, `TODATE`, `SERVICE_YEAR` | dates |
| `TYPE` | `CHARGE` / `PAYMENT` / `TRANSFERIN` / `TRANSFEROUT` |
| `TRANSFERTYPE` | whose responsibility: `1` primary payer, `2` secondary, `p` patient |
| `METHOD` | payment channel: `ECHECK` = insurer; `CASH`/`CHECK`/`CC`/`COPAY` = patient |
| `PROCEDURECODE`, `IS_ADMIN_NOISE_CODE` | flag is TRUE for code 185347001 |
| **`BILLED_AMOUNT`** | **derived** — `AMOUNT` on CHARGE rows only, 0 elsewhere |
| `PAID_AMOUNT` | `PAYMENTS`, already 0 off PAYMENT rows |
| **`PAID_BY_PAYER`** | **derived** — PAYMENT rows where `METHOD = 'ECHECK'` |
| **`PAID_BY_PATIENT`** | **derived** — PAYMENT rows where `METHOD <> 'ECHECK'` |
| `TRANSFER_AMOUNT` | `TRANSFERS` |
| `OUTSTANDING_RUNNING_BALANCE` | **renamed deliberately** — see §26.1 |
| `PAYER_ID`, `PAYER_NAME`, `PAYER_CITY`, `PAYER_TYPE` | `PAYER_NAME` = the insurer; `PAYER_ID` keys insurer × city |
| `ENCOUNTERCLASS` | care setting |

Per §1 rule 5, the three **derived** columns are marked as such — they do not
exist in the source.

### `CODE_DICTIONARY` — column reference

| Column | Notes |
|---|---|
| `CODE`, `DESCRIPTION` | canonical name; `MODE()` resolves casing variants |
| `SEMANTIC_TAG` | SNOMED qualifier (`disorder`, `procedure`, `finding`…). Present on 71.6% of codes |
| `SOURCE_TABLES` | provenance — which tables the code appears in |
| `CODE_CATEGORY` | Condition / Procedure / Encounter type / Medication or vaccine / Device or supply / Substance / Social determinant / Administrative / Mortality event / Imaging |
| **`IS_CONDITION`** | the flag for ranking conditions by cost |
| `IS_CLINICAL` | broader — excludes admin, social, devices, venues |
| `CLASSIFIED_BY` | `semantic_tag` (690) / `provenance` (284) / `manual_override` (25) |

`CLASSIFIED_BY` exists so any classification is traceable and correctable with
a one-line `UPDATE` — satisfying §16 (traceability to source columns).

---

## 26. Dataset-Specific Traps

Each of these produces a **plausible wrong answer, not an error**. The curated
layer neutralises all of them; these notes matter when querying raw tables.

### 26.1 `OUTSTANDING` is a running balance, not A/R

`SUM(OUTSTANDING)` returns **$45,314,446,541**. Genuinely uncollected revenue
is **$83,363.50** — a **543,000×** overstatement. The column is stamped on
every row as money moves through the transfer chain, so summing counts the same
balance at each stage.

Correct measure: the balance on each claim's **last** transaction.

### 26.2 `AMOUNT` appears on transfer rows

Populated on `TRANSFERIN` as well as `CHARGE`. Summing it inflates spend by
**$23.4B (~17%)**. Use `BILLED_AMOUNT`.

### 26.3 `PAYER_ID` is who was billed, not who paid

Responsibility can shift to the patient mid-claim. Using `PAYER_ID` alone
misattributes **$20.3B** of patient payments to insurers. Use `METHOD` on
PAYMENT rows.

### 26.4 `DIAGNOSIS1` is mostly not a diagnosis

On a 1% sample, **50.6%** is copied from `ENCOUNTERS.REASONCODE` and **13.9%**
from `ENCOUNTERS.CODE`. Only **46.7%** of claims carry a real condition in
position 1; **18.4%** of its uses are procedure codes.

The convention is **inverted** — `DIAGNOSIS2`–`8` contain zero procedure codes
and get progressively cleaner (59.8% → 98%).

Use `CODE_DICTIONARY.IS_CONDITION`, and consider the **DIAGNOSIS2 fallback**
(use position 1 when it is a condition, else position 2), which recovers
5,939,894 claims. Both versions are kept; the fallback attributes full claim
cost to a nominally secondary diagnosis, which is a trade-off, not a strict
improvement.

### 26.5 `PROCEDURECODE` mixes three code systems

Procedure, SNOMED encounter, and RxNorm drug codes all appear. Resolve through
`CODE_DICTIONARY`, not a single source table.

### 26.6 `PAYER_ID` keys an insurer **× city** pair

120 rows for 10 insurers. Group by `PAYER_NAME` for the insurer; by
`PAYER_ID`/`PAYER_CITY` to keep the regional split. This is a grain trap
(§6), not corrupt data — each row carries genuine per-city figures.

### 26.7 Claim counts are not additive across procedure rows

Summing gives 249.0M against 124.1M actual claims — exactly **2.0×**, because
the average claim carries two procedures. Correct within a row; never summed
across rows.

### What this dataset cannot answer

Per §22 (do not manufacture certainty), these return zero **by construction**:

- **Denials, write-offs, bad debt.** Collection is 100%; `ADJUSTMENTS` is 0 on
  all 887M rows. Verified: net gap of **−$1,392** across 9,054 procedure ×
  payer combinations.
- **Days in A/R.** 98.66% of claims are paid the same day. The 1.3% tail tracks
  encounter duration, not payment lag.
- **Equity conclusions from demographics.** Synthea generates demographics from
  census distributions; any finding would be a generator artifact.
- **Absolute price realism.** Allergy immunotherapy bills $11,122/injection
  against a real-world $50–200. Rankings hold; magnitudes do not.
- **Hospital rankings by total spend.** These track simulated city size (9 of
  the top 10 are Cleveland). Use **cost per patient** instead.

---

## 27. Questions Answered

Following §12, each is stated as observation → interpretation → recommendation.

### Q1 — Where does the money go?

**Observation.** The top 20 conditions account for **90.8%** of
condition-attributable spend ($72.7B) and **66.6%** of all spend ($99.1B).
Normal pregnancy alone is **39.8%**. Ranking by cost *per patient* reorders the
list sharply: gingivitis spreads **$10,661** across 800,465 patients, while
non-small-cell lung carcinoma concentrates **$1,416,145** into 2,384.

**Why — spend decomposed.** Spend is the product of three drivers:

```
spend = patients  x  claims per patient  x  cost per claim
```

Against the median condition (4,167 patients, 2.1 claims each, $731/claim), the
top 20 are not extreme on any one driver — they are *moderately* extreme on all
three at once, and the multiplication does the rest:

| | Top 20 | Other 165 | Ratio |
|---|---|---|---|
| Median patients | 41,489 | 3,456 | 12x |
| Median claims per patient | 10.8 | 2.0 | 5.4x |
| Median cost per claim | $3,416 | $607 | 5.6x |
| **Average billed per condition** | **$3.30B** | **$40.6M** | **81x** |

Across all 185 conditions this yields four archetypes — **61 reach-driven,
58 balanced, 44 price-driven, 22 frequency-driven**:

- **Reach** — gingivitis at 192x the median patient count
- **Frequency** — small cell lung cancer at 317.7 claims per patient, chronic
  kidney disease at 258.5 (dialysis three times weekly)
- **Price** — stroke at $70,715 per claim, 97x the median

**Interpretation.** The 90% concentration is not one phenomenon but three
failure modes stacked in one list. Gingivitis is a volume problem, CKD a
frequency problem, stroke a price problem. A single "reduce high-cost
conditions" programme would address none of them well.

**Recommendation.** Segment cost programmes by *shape*, not by rank. Volume
conditions respond to prevention and access; frequency conditions to
care-pathway management; price conditions to acuity and site-of-care
management. Always report cost per claim beside claims per patient — their
product is cost per patient, and showing the product alone hides which lever
applies.

#### Pregnancy at 39.8% is arithmetically correct but NOT realistic

Tested because it is the single largest fact in Q1. The utilisation is
plausible; the pricing is not.

| | This data | Real US | Verdict |
|---|---|---|---|
| Cost per pregnancy | **$161,988** | ~$18,865 (KFF 2022) | **8.6x too high** |
| Claims per pregnancy | 11.1 | 10–15 visits | plausible |
| Cost per claim | **$14,550** | $100–300 per prenatal visit | implausible |

Cause: Synthea bills each routine prenatal check as a separate ~$5,000
procedure. **Four** of them carry **68.3%** of all pregnancy spend — the top
two alone are 55.1%:

| Line item | Billed | Per line | Reality |
|---|---|---|---|
| Evaluation of uterine fundal height | $7.97B | $4,968 | a tape measure, bundled into the visit |
| Auscultation of the fetal heart | $7.97B | $4,967 | a Doppler held to the abdomen, bundled |
| Ultrasound for fetal viability | $2.44B | $8,879 | ~$200–500 |
| Standard pregnancy test | $1.37B | $4,966 | ~$10–20 |

Price those four at zero (i.e. bundled, as they are in reality) and pregnancy
falls from **$28.9B to $9.2B — 39.8% to 17.3%** of condition-attributable
spend. Still first, no longer dominant.

This is the query that found the pricing problem, so it is worth knowing what
it does and does not claim. **A procedure is not owned by a condition** — the
claim carries the diagnosis and the procedures are line items hanging off it,
so the output is what was billed *on claims attributed to* each condition. The
same hemogram appears under many conditions. It reads `DIAGNOSIS1` directly
with no DIAGNOSIS2 fallback, and covers only the two largest conditions;
adding another means adding its code to the `target` list.

The allergy cut is the cleaner demonstration of the same defect, because one
line item is essentially the whole condition: **subcutaneous immunotherapy is
98.5% of allergy spend at $11,122 a shot** against a real-world $50–200, billed
765,286 times. The encounter containing it is priced at $118 — correctly. That
juxtaposition inside a single condition is the evidence that Synthea prices
*encounters* realistically and *procedures* at a flat few thousand dollars
regardless of what the procedure is.

*Query:* `sql/analysis/q1_condition_procedures.sql` ·
*Results:* `q1_pregnancy_procedures_2020_2024.csv` (86 rows),
`q1_allergy_procedures_2020_2024.csv` (18 rows)

**This is systemic, not pregnancy-specific.** Allergy immunotherapy bills
$11,122 per injection against a real $50–200; a hemogram bills $1,897 against
a real $10–30. Treat every absolute dollar figure in this project as
unrealistic in magnitude. **Rankings and ratios hold; totals do not**, and
conditions whose pathway repeats many cheap procedures are inflated hardest.

#### Why the prices are wrong: clinical fidelity vs financial fidelity

Not simply "because it is synthetic" — different parts of this dataset have
very different reliability, and knowing which is which is what makes it usable.

**Synthea models clinical realism, not financial realism.** The care pathways
are the part it was designed and validated for, and they hold up:

| Pattern | This data | Real world |
|---|---|---|
| Prenatal visits per pregnancy | 11.1 | 10–15 |
| Immunotherapy sessions per patient | 17.9 | multi-year course of repeated shots |
| Dialysis claims per CKD-4 patient/yr | 258.5 | three times weekly |

Costs were layered on afterwards and far more crudely — procedures appear to
draw on coarse default prices rather than a real fee schedule. The tell is that
**23 different prenatal labs are all priced within $10 of each other at
~$1,895**, and a tape-measure check is priced like a lab panel. Nothing
distinguishes them because the price never came from what the procedure is.

So one dataset carries **high-fidelity clinical patterns under low-fidelity
pricing.**

**Do not blame synthetic data for all of it.** Real claims data is also strange
about price: hospital *billed* amounts are chargemaster figures that can run
5–10x what anyone actually pays, so inflated billed amounts are not unique to
simulation. What real data would additionally show is negotiated rates,
contractual adjustments and payer-specific pricing. Their **absence** is the
clearer synthetic tell here — `ADJUSTMENTS` is 0 on all 887M rows and payer
type moves price by only 1.06x.

**Practical rule.** Trust the clinical structure — who receives what care, how
often, in which setting. Treat the dollars as **relative weights, not amounts**.
Rankings, shares and ratios are usable; absolute totals are not.

#### Does cost vary by payer or hospital?

- **By payer type: no.** Median spread across Government, Commercial and
  Self-Pay is **1.06x**. This follows from `ADJUSTMENTS` being 0 on all 887M
  rows — there are no negotiated rates, so the same service is billed
  identically whoever pays. Payers differ in what share they *cover* (Q2), not
  in what they are charged.
- **By hospital: for a few conditions.** Of the ten highest-spend conditions,
  only breast cancer (0.97) and normal pregnancy (0.96) show real spread
  between *typical* hospitals; the other eight sit at 0.17–0.45.

The metric is **(P75 − P25) / median** of cost per claim across hospitals — the
price gap between the cheapest and dearest quarter of hospitals, as a share of
the typical price. It is reported instead of max/min because the two disagree
sharply and max/min misleads: ESRD reads **163x** on max/min but only **0.17**
on this measure, meaning typical hospitals bill near-identically and one or two
outlier sites create the range. Ordering a chart by max/min highlights exactly
the conditions whose variation is illusory.

Volume floors are mandatory here: >=30 claims per hospital-condition pair and
>=20 hospitals per condition. Without them, conditions with 7 to 21 claims
top the ranking.

*Queries:* `sql/analysis/q1_cost_drivers.sql`, `q1_cost_variation.sql`,
`q1_hospital_variability.sql`
*Results:* `q1_cost_drivers_2020_2024.csv`,
`q1_spend_decomposition_2020_2024.csv`,
`q1_hospital_cost_spread_2020_2024.csv`,
`q1_hospital_variability_2020_2024.csv`
*Charts:* `dashboard/where_the_money_goes.html` (three charts),
`dashboard/q1_donut.html`

### Q2 — Who actually pays?

**Observation.** Patients bear **20.4%** of all spend — **$20.3B**, or
**$16,084** per patient over five years. The burden is **inverted against
cost**: patients pay **41.6%** of wellness visits but **8.6%** of inpatient
stays. By coverage, a government-covered patient pays **$2,118** over five
years, a commercially-insured one **$19,178**, and an uninsured one
**$61,742** — despite government patients being billed *more* care overall.
Every ratio is flat across 2020–2024.

**Interpretation.** The mechanism is measured rather than assumed, and it
works differently for each kind of insurance. Government patients pay a flat
$0–50 per claim whatever its size, so their share shrinks arithmetically as
bills grow. Commercial patients pay roughly half of a small claim and very
little of a large one — but not because of any per-claim rule. On larger
claims a growing proportion of patients have already exhausted their **annual
out-of-pocket maximum** and pay nothing at all. Measured in $500 bands, the
share of commercial claims where the patient pays exactly zero climbs from
**14% around $3,500 to 64% around $7,500**, while the aggregate patient share
falls from **54% to 17%** over the same range. It is a taper, not a cliff —
nothing switches off at a threshold.

**The limit is annual, so cumulative spend matters more than claim size.**
What determines whether a patient still owes anything is not how large one
claim is but how much they have already spent that year. The data agrees:
across care types, patient share tracks **cost per person** (Spearman
**−0.72** among commercial patients) considerably better than it tracks
**median claim size** (**−0.40**). Claim size is a proxy for the annual total,
not the quantity the cap acts on.

**The pattern is not an artefact of payer mix.** Government patients pay
almost nothing, so a care type weighted towards them reads low-share whatever
it costs — and across all 15 care types, patient share tracks the government
share of spend (−0.57) nearly as strongly as it tracks cost (−0.60). Splitting
by payer type settles it: the cost relationship **strengthens** inside each
group (commercial **−0.72**, government **−0.88**), because blending two
populations with very different payment levels was adding noise rather than
creating the trend (`q2_pattern_within_payer.sql`). Cost-sharing falls hardest
on exactly the preventive care that health policy tries to make frictionless,
and stability across five years indicates benefit design rather than drift.

**This is Synthea's benefit generator, not US insurance.** Real plans carry
deductibles, tiers, networks and negotiated rates that this data does not
model. The mechanism above explains how the simulation assigns cost-sharing.
It should not be read as a finding about how insurance actually works.

**Recommendation.** Where the goal is preventive uptake, flat copays are
counterproductive — the mechanism, not the rate, is the lever. For providers,
payer mix determines collection risk: **$20.3B must be collected from
individuals rather than institutions**, and ambulatory care alone carries
$12.7B (63%) of it.

*Queries:* `sql/analysis/q2_who_pays.sql`, `q2_who_pays_by_year.sql`,
`q2_commercial_cap_by_care_type.sql`,
`q2_pattern_within_payer.sql`, `q2_pattern_breakers.sql`

#### Which conditions cost patients the most, and why

Patient out-of-pocket by condition is **total billed x patient share**, so it
is largely a restatement of Q1 — the two rankings correlate at
**Spearman rho = 0.971**. A condition tops the out-of-pocket list mainly
because it is expensive overall.

But patient share is not constant (**0% to 78.8%, median 27.3%**), and that
spread reshuffles the list systematically:

| Condition | Rank by spend | Rank by patient cost | Patient share |
|---|---|---|---|
| Viral sinusitis | 44 | **25** | 51.7% |
| Acute viral pharyngitis | 27 | **16** | 43.5% |
| Acute bronchitis | 18 | **9** | 33.3% |
| Primary dental caries | 14 | **8** | 30.3% |
| Malignant neoplasm of breast | 7 | **20** | 8.0% |
| Small cell lung cancer | 13 | **28** | 6.4% |
| Chronic congestive heart failure | 23 | **39** | 8.5% |
| Malignant tumor of colon | 25 | **44** | 7.3% |

This is the same inversion found by care setting, now at condition level:
**the cheaper and more routine the illness, the larger the share the patient
carries.** Sinusitis patients pay 51.7% of the bill; colon cancer patients pay
7.3%.

**Report these as two separate questions, because they have different
answers:**

1. *Which conditions cost patients the most in total* — driven almost entirely
   by overall spend. Pregnancy ($4.93B) and gingivitis ($2.43B) are 57.6% of
   all patient out-of-pocket.
2. *Which conditions expose patients to the greatest share of the bill* — a
   genuinely different list, topped by sinusitis, pharyngitis and bronchitis,
   none of which appear in the top ten by spend.

The first tells you where aggregate dollars land; the second tells you what a
person feels when they get ill. Clinically they are near-opposites — the first
list is pregnancy and cancer, the second sore throats and sinus infections.

Total patient out-of-pocket attributable to a condition is **$12.77B**; the
top 20 conditions carry **88.1%** of it. Dental (gingivitis, gingival disease,
caries, tooth infection) is **$3.0B — 23.4%** of the total, at patient shares
of 26–30%.

*Query:* `sql/analysis/q2_oop_by_condition.sql` ·
*Results:* `q2_oop_by_condition_2020_2024.csv`

#### The blended patient share hides a large gap between insurance types

The headline "patients bear 20.4%" and every per-condition share is a
**blend across insurance types**, and for many conditions nobody actually
experiences the blended number.

Taking the ten conditions where patients carry the largest share of the bill
(minimum 5,000 people affected, so a handful of patients cannot top the list):

| Condition | Everyone | Commercial | Government | Commercial worse by |
|---|---|---|---|---|
| Concussion with loss of consciousness | 67.9% | 72.4% | 58.2% | +14.2 pts |
| Concussion, no loss of consciousness | 67.6% | 71.4% | 58.5% | +12.9 pts |
| **Prediabetes** | 62.2% | **84.9%** | **8.1%** | **+76.8 pts** |
| Concussion injury of brain | 61.8% | 71.6% | 45.0% | +26.6 pts |
| Otitis media | 61.5% | 80.5% | 33.0% | +47.5 pts |
| Asthma | 57.5% | 66.0% | 42.6% | +23.4 pts |
| **Obesity (BMI 30+)** | 56.0% | **86.7%** | **8.5%** | **+78.2 pts** |
| Sprain | 55.4% | 71.1% | 31.6% | +39.5 pts |
| Fracture subluxation of wrist | 54.3% | 63.6% | 44.0% | +19.6 pts |
| Fracture of clavicle | 54.3% | 62.0% | 44.4% | +17.6 pts |

**Commercial patients pay more than government patients on every one**, never
by fewer than 12.9 points. Prediabetes and obesity are the extremes:
government covers ~92% of the bill, commercial ~14%, so a commercially
insured patient pays roughly **ten times the share** for the same condition.
Both are chronic-risk conditions managed through routine screening and
counselling — precisely the cheap-visit territory where a flat copay absorbs
most of the bill.

**Patients out-pay both insurers combined on 9 of these 10.** Obesity:
patients $42.8M against $33.6M from all insurers together. Otitis media:
patients $28.8M against $18.0M.

**Rule for reporting:** never quote a blended patient share for a condition
without splitting it by insurance type. Prediabetes reads 62.2% overall and
nobody pays 62.2% — commercial patients face 84.9%, government patients 8.1%.
The blend is an artifact of who happens to be insured how.

#### Two different questions about patient cost

These have almost disjoint answers and must not be conflated:

| | Ranked by money patients paid | Ranked by share of the bill |
|---|---|---|
| #1 | Normal pregnancy — $4.93B | Concussion — 67.9% |
| Share of the bill | 17.0% | 67.9% |
| Money involved | $4,927,384,330 | $443,599 |

None of the top ten by money ranks better than **#76 of 183** on share
(acute bronchitis); pregnancy sits at #133, lung cancer at #175. Conversely
the best "rank by money" among the top ten by share is otitis media at #35.

Concussion is the clearest illustration. Across all three concussion codes:
**91,963 claims, 46,783 people, $9.0M total bill, $98 per claim.** Patients
pay 63.8% of it — which is **$123 per person over five years**. The share is
extreme; the money is trivial. Losing consciousness does not change the
economics (67.9% with, 67.6% without), because a $98 bill is small enough
that a copay swallows most of it regardless of severity.

So: **money tells you where the spending is; share tells you where the system
leans hardest on the individual.** The first list is pregnancy and cancer, the
second is concussions, ear infections and sprains.

*Queries:* `sql/analysis/q2_top10_patient_paid.sql`,
`q2_top10_by_share_of_bill.sql`, `q2_top10_share_by_payer_type.sql`,
`q2_concussion_detail.sql`, `q2_burden_by_setting_and_payer.sql`,
`q2_spend_vs_patient_cost_rank.sql`

#### Grouping conditions into types of care

A single condition is rarely the unit a decision gets made in. Dental care is
one budget, one benefit design and one policy lever, but it reaches the data as
fifteen separate conditions. Grouping the 185 conditions into **15 types of
care** turns the per-condition findings above into something addressable.

The grouping is a keyword classification over the condition name, written out
in full in the query so it can be read and corrected rather than trusted. Order
matters — dental is tested first, so `Infection of tooth` and
`Fracture of mandible` group as dental rather than as infection or injury.
Unmatched conditions fall to **Other**, which is reported rather than hidden:
38 of the 185 land there, but they carry **0.1%** of patient dollars and
**0.12%** of the bill, so the taxonomy covers essentially all of the money.

**How the percentages are calculated.** The share is *money patients paid ÷
total money paid* on the claims attributed to that type of care — **not a share
of the amount billed**, though with collection at 100% here the two differ only
by rounding. Who paid comes from `METHOD` on PAYMENT rows (`ECHECK` = insurer,
`CASH`/`CHECK`/`CC`/`COPAY` = the patient), never from `PAYER_ID`, which records
who was *billed* and would misattribute $20.3B of patient payments to insurers
(§26.3). Money is totalled per `CLAIM_ID` first and then grouped, so a claim
carrying several procedure rows is counted once (§26.7). A claim joins a care
type through `DIAGNOSIS1` when that is a real condition and `DIAGNOSIS2`
otherwise. The window is 2020–2024 and `IS_ADMIN_NOISE_CODE` is excluded.

**Observation.** Ordered by money patients paid (8 of 15 rows; the full table is
in the results file):

| # | Type of care | Paid by patients | % of all patient spend | % of bill | Rank by share | People | Commercial | Government |
|---|---|---|---|---|---|---|---|---|
| 1 | Maternity | $4.94B | 38.7% | 17.0% | #10 | 178,766 | 15.1% | 0.6% |
| 2 | **Dental & oral** | **$3.30B** | **25.8%** | 27.9% | **#4** | 938,009 | 52.9% | 3.0% |
| 3 | Allergy & immune | $863.0M | 6.8% | 10.0% | #13 | 49,452 | 6.7% | 0.7% |
| 4 | Kidney & urinary | $857.1M | 6.7% | 14.2% | #12 | 167,126 | 14.3% | 2.7% |
| 5 | Respiratory & ENT | $668.4M | 5.2% | 26.8% | #5 | 937,507 | 44.5% | 5.8% |
| 6 | Cancer & tumours | $589.2M | 4.6% | 8.3% | #15 | 67,860 | 17.3% | 1.1% |
| 10 | Diabetes & metabolic | $159.2M | 1.2% | 36.6% | **#2** | 259,513 | 74.4% | 8.1% |
| 13 | Blood disorders | $47.2M | 0.4% | 38.9% | **#1** | 67,419 | 56.2% | 2.9% |

Three things fall out of the regrouping:

1. **Maternity and dental carry 64.5% of everything patients pay** — 38.7% and
   25.8%. Dental is the one worth isolating: **938,009 distinct people**,
   against maternity's 178,766. It is the largest patient-cost category that is
   not a single life event, and the only group in the top four on *both*
   rankings (#2 by money, #4 by share). Every other high-share group is trivial
   in dollars — blood disorders leads on share at 38.9% but is 13th of 15 on
   money — and every other high-money group is low on share.
2. **Money and share disagree here as they do at condition level.**
   Diabetes & metabolic ranks **10th by dollars but 2nd by share** (36.6%);
   maternity is **1st by dollars and 10th by share** (17.0%).
3. **The insurance-type gap survives the regrouping and is never small.**
   Commercial patients carry a larger share than government patients in **all
   15 groups**, never by fewer than 6 points. Diabetes & metabolic is the
   extreme — 74.4% against 8.1%, a **9.2×** gap on the same care — which is the
   prediabetes/obesity finding above reappearing at group level.

**Interpretation.** The two largest patient-cost groups are opposite in kind.
Maternity is few people (178,766) meeting a very large bill ($162,288 each over
five years) at a low share. Dental is five times as many people (938,009)
meeting a modest bill ($12,610) at a high share. Aggregate dollars alone cannot
tell those apart, and they do not respond to the same intervention.

**Recommendation.** Treat dental as the first candidate for benefit redesign: it
is one coherent benefit, the largest patient-cost group outside a life event,
and its 27.9% share falls on close to a million people. Where the goal is to
reduce what individuals pay rather than what the system spends, sort by the
share column, not the dollar column.

**Dental was split and merged back.** Preventive (gum disease, torus palatinus —
managed by cleaning and monitoring) against restorative (everything repairing or
replacing structure) measured as **$2.68B preventive to $615.2M restorative, a
4.4× gap**, reaching **843,089 people against 371,650**, at **$3,179 per person
against $1,655**, at shares of 28.2% and 26.4%. So the dental burden is gum
care, not tooth repair. The split was merged back for reporting because a single
dental line is the unit the benefit is designed in; the figures are kept here
because the finding is real. To reproduce it, replace the dental branch in the
query with a `(gingiv|palatinus)` branch tested ahead of the rest. Note that
276,730 people carry both kinds of dental condition, so the two groups overlap.

**Reconciliation** (per §24). Total bill across the 15 groups is
**$72,685,492,673** against the reference $72,685,492,693 — $20 apart from
per-row rounding. Patient out-of-pocket totals **$12,772,723,565**, matching the
$12.77B in the per-condition cut above, and all 185 conditions are accounted
for. The merge was verified to restore the pre-split dental row to the dollar.

**The two care types that appear to break the cost/share rule do not.**
`Infections (other)` costs $24,715 per person yet patients carry 28.0%, and
`Brain & nervous system` costs $8,939 yet they carry 8.5%. Neither is a
counter-example. Infections only looks dear on a per-person basis: its median
claim is **$1,542** against a mean of $5,466, so the typical claim sits well
under the cap and a small number of very large ones lift the average. `Brain &
nervous system` is **90.2% government-funded spend**, the highest of the 15
groups, and government patients pay a flat $0–50 whatever the bill — the group
reads low-share because of who pays for it, not what it costs
(`q2_pattern_breakers.sql`).

**Caveats.**

- **`People affected` is not additive across groups.** It sums to 3,476,252
  against 1,259,375 patients with spend (**2.76×**) — someone with gingivitis
  and asthma is counted under both. Correct within a row; never summed down the
  column (§6).
- **The taxonomy is a judgment call**, like the `Stress` classification. It
  lives in one readable `CASE` expression, so any grouping moves with a one-line
  edit and a re-run.
- **The groups are broad enough that splitting them can compare unlike things.**
  Below $5,000, `Kidney & urinary` is 91% dialysis at $459 a claim; above it,
  100% bladder infections at $7,620. Any cut that separates small claims from
  large ones within a care type may be separating conditions, not price bands
  (`q2_cap_reversal_diagnosis.sql`).
- Inherits the **DIAGNOSIS2 fallback** and therefore its trade-off.
- **The shares are blends across insurance type**, and per §27 above should not
  be quoted alone — nobody pays diabetes care's blended 36.6%. The blend also
  compresses the spread: commercial patient share across these groups runs
  **6.7% to 74.4%**, government **0.6% to 8.1%**. Commercial diabetes patients
  carry **74.4%** of their own care (`q2_pattern_within_payer.sql`).
- **Cost per person mixes claim size with visit frequency**, and only the first
  interacts with the cap. A group can read as dear per person because people
  attend often while every individual claim stays small — which is exactly what
  `Infections (other)` does. Read median claim alongside it.
- Dental and maternity magnitudes carry the project-wide pricing caveat: the
  **ranking and the ratios** are the usable parts, not the absolute dollars.

*Query:* `sql/analysis/q2_patient_cost_by_care_type.sql` ·
*Results:* `q2_patient_cost_by_care_type_2020_2024.csv` ·
*Chart:* `dashboard/q2_who_bears_the_cost.html`

### Q3 — How concentrated is spend?

**Scope: this question rests on patients and hospitals.** Concentration is
measured at four grains, and two of them return answers Q1 already gave:

| Ranked by | How many exist | Needed for half the spend | New here? |
|---|---|---|---|
| Conditions | 185 | 2 | No — Q1 already has pregnancy at 39.8% |
| Care types | 15 | 2 | No — Maternity is 99.7% Normal pregnancy |
| Hospitals | 3,918 | **86** | **Yes** |
| Patients | 1,259,375 | **134,198** | **Yes** |

The condition and care-type rows are kept in the query so the duplication is
demonstrated rather than assumed, but they carry no conclusion of their own —
"2 care types cover half" is pregnancy plus dental, which Q1 and Q2 both already
report. Read Q3's answer off the bottom two rows.

**Observation.** **86 hospitals** cover half of all spending, while it takes
**134,198 patients (10.7%)** to reach the same mark — a gap of three orders of
magnitude between the two. Among 731 hospitals with ≥1,000 patients, cost per
patient ranges **$4,401 to $144,422 — a 32.8× spread**. Across those sites the
spread tracks **cost per visit** (Spearman +0.81) slightly more closely than
**visits per patient** (+0.65), so both drive it. The extreme tail behaves
differently: nine of the ten dearest sites are VA and veterans' facilities
seeing each patient **47–55 times** against a median of **4.5**, at per-visit
prices of $1,978–$2,926 that straddle the $2,632 mean.

**Interpretation.** Spend concentrates in *places*, not in *people*. A small
set of sites carries the money while the patient population behind it is
broad, which is the one thing Q3 establishes that no other question can —
neither Q1 nor Q2 counts patients at all. Among hospitals, price and frequency
both matter, with price somewhat the stronger of the two — but the handful of
sites at the very top are expensive almost purely through frequency, at
ordinary per-visit prices. Those are two different problems wearing the same
number.

**Recommendation.** Target the 86 sites that cover half of spend — small
enough to address individually, and the actionable half of this question. Do
not build a case-management programme around high-cost patients: at 134,198
people for half the spend, there is no small group of patients to manage.
Split the hospital approach by where a site sits in the distribution: price
negotiation across the broad middle, where cost per visit is the stronger
lever, and chronic-care management for the small tail of VA sites whose
patients return roughly ten times more often than typical.

*Correction (2026-08-27).* This subsection previously read "the hospital spread
is a frequency effect, not a pricing one" and recommended chronic-care
management over price negotiation on that basis. That was the top-ten pattern
generalised to all 731 sites; the correlations above show price is in fact the
marginally stronger driver overall. The tail finding stands, the general claim
did not.

*Queries:* `sql/analysis/q3_concentration.sql`, `q3_top_entities.sql`,
`q3_hospital_cost_intensity.sql` ·
*Chart:* `dashboard/concentration.html`

#### What a typical claim, visit and patient actually costs

Concentration says a few cases carry the total. The distribution says the same
thing from the other end, and it is the reason **no average in this project
should be quoted without its median**.

**Observation.** Cost is heavily right-skewed at every grain, and the mean sits
far above the median in all three:

| Grain | Count | Median | Mean | Mean ÷ median | p99 | p99 ÷ median | Max |
|---|---|---|---|---|---|---|---|
| Per claim | 68,645,121 | $275.59 | $1,454.22 | **5.28×** | $19,765.14 | 71.7× | $822,680 |
| Per visit | 35,272,859 | $966.81 | $2,830.08 | **2.93×** | $28,300.13 | 29.3× | $822,680 |
| Per patient | 1,259,375 | $30,292.02 | $79,265.52 | **2.62×** | $550,836.53 | 18.2× | $6,716,961 |

**Interpretation.** The skew is real but it *falls* as the grain widens — 5.28×
per claim, 2.93× per visit, 2.62× per patient. Aggregating averages the tail
away: a patient's year contains many ordinary claims alongside the expensive
one, so extreme claims do not produce proportionally extreme patients. That is
the distributional form of the Q3 finding that spend concentrates in conditions
and sites rather than in catastrophically sick individuals (top 1% of patients
= 11.8%, against a real-world 20–25%).

**Recommendation.** Report the median as the typical figure and the mean only
alongside it. A mean claim of $1,454 describes almost no claim in the data —
75% of claims are under $862.63.

**Caveats.**

- Percentiles use `APPROX_PERCENTILE` (t-digest), so they are **approximate**;
  counts, totals and means are exact. Fine at these magnitudes, not for a
  figure quoted to the cent.
- Grains are not comparable populations. Per-visit covers 35.3M visits with
  billed spend, not the 64.5M rows in `ENCOUNTERS`.
- The column headers in this file are the raw SQL names (`P50_MEDIAN`,
  `MEAN_OVER_MEDIAN`), which predate the plain-language naming rule in §21 and
  do not follow it.

**Reconciliation** (per §24). All three grains total **$99,825,019,809**, the
all-spend reference; per-claim n = 68,645,121 and per-patient n = 1,259,375
match the claims and patients references exactly.

*Query:* `sql/analysis/01_percentiles.sql` ·
*Results:* `cost_percentiles_2020_2024.csv` (3 rows)

### Cross-cutting limitations

Per §12 and §22, these travel with any presentation of the above:

1. Patient concentration (top 1% = 11.8%) is **flatter than real US claims
   data** (20–25%), because Synthea generates patients independently.
2. The DIAGNOSIS2 fallback attributes full claim cost to a **secondary**
   diagnosis; the conservative position-1-only cut is retained for comparison.
3. `Stress` is classified as a social determinant rather than a condition — a
   judgment call, reversible with a one-line `UPDATE`.
4. Nothing meaningfully trends over 2020–2024. **Stability is the finding**;
   the interesting variation is cross-sectional.
