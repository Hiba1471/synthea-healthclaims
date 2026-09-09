# Methodology

How the raw share was cleaned, what was derived from it, and why each decision
was made. Field definitions are grouped by the layer that creates them, since
each layer reads only from the one below it.

Companion documents:

- [`DATA_QUALITY_LOG.md`](DATA_QUALITY_LOG.md) — every defect found in the source,
  with evidence and resolution.
- [`DATA_DICTIONARY.md`](DATA_DICTIONARY.md) — table and column reference for
  the share and the curated layer.

---

## Cleaning

The share is read-only, so nothing is fixed at source. Corrections live in a
curated view that every query reads through.

The defects are not missing values or bad formatting. They are columns that
answer a different question than their name suggests, which means a wrong
result looks entirely reasonable and nothing errors. That shaped the approach:
rather than validating types and null rates, each money column was measured a
second way and the two answers compared. Where they disagreed, one of them was
measuring the wrong thing.

| Step | What it does | Why |
|---|---|---|
| Rebuild money columns | Derive billed and paid from transaction type and payment method | `AMOUNT` is populated on transfer rows too, and `PAYER_ID` records who was billed rather than who paid |
| Rename, don't drop | `OUTSTANDING` → `OUTSTANDING_RUNNING_BALANCE` | Dropping it sends the next person to the raw table unwarned; the new name makes `SUM()` visibly wrong |
| Collapse payers | 120 payer rows → 3 plan types | `PAYER_ID` keys an insurer-*city* pair, not an insurer |
| Apply the window | `FROMDATE` 2020-01-01 to 2024-12-31 | Unfiltered the data runs back to 1914, and volume steps up ~8× in Nov 2019 |
| Flag admin noise | `IS_ADMIN_NOISE_CODE` on procedure code 185347001 | A single non-clinical code carries $713.7M; flagged rather than deleted so its size stays measurable |
| Resolve codes | Union eleven source tables into one dictionary | Code fields mix SNOMED, RxNorm and DICOM, so ~30% of diagnosis spend will not join on one table alone |

Rows are never dropped for being unusual. Exclusions are expressed as flags, so
any analysis can put them back and see what changed.

Full detail, including how each defect was found and what it cost, is in
[`DATA_QUALITY_LOG.md`](DATA_QUALITY_LOG.md).

---

## Engineered fields

### Layer 1 — `V_CLAIMS_TX_CLEAN`

Source: [`sql/ddl/v_claims_tx_clean.sql`](sql/ddl/v_claims_tx_clean.sql)

| Field | Definition | Reasoning |
|---|---|---|
| `BILLED_AMOUNT` | `AMOUNT` when `TYPE = 'CHARGE'`, else 0 | Transfers move an existing balance rather than creating new money, so summing raw `AMOUNT` counts a dollar once as a charge and again at each transfer |
| `PAID_BY_PAYER` | `PAYMENTS` when `TYPE = 'PAYMENT'` and `METHOD = 'ECHECK'`, else 0 | `METHOD` is the only reliable signal of who actually paid |
| `PAID_BY_PATIENT` | `PAYMENTS` when `TYPE = 'PAYMENT'` and `METHOD <> 'ECHECK'`, else 0 | Cash, cheque, card and copay are all the member paying directly |
| `PAID_AMOUNT` | `PAYMENTS`, unchanged | Kept so member and payer parts can be checked against the total |
| `OUTSTANDING_RUNNING_BALANCE` | `OUTSTANDING`, renamed | Stamped on every row as money moves; terminal A/R is the balance on each claim's chronologically last transaction |
| `PAYER_TYPE` | Medicare / Medicaid / Dual Eligible → Government; `NO_INSURANCE` → Self-Pay; else Commercial | The two designs behave in opposite directions as a bill grows, so a blended figure averages populations that never overlap |
| `IS_ADMIN_NOISE_CODE` | `PROCEDURECODE = 185347001` | Non-clinical encounter code; flagged, not filtered |
| `SERVICE_YEAR` | `YEAR(FROMDATE)` | The standard grain for every trend |

**Money rows are not interchangeable.** `BILLED_AMOUNT` is non-zero only on
charge rows; the paid columns only on payment rows. No row carries both. A
filter that looks harmless — `BILLED_AMOUNT > 0` — silently drops every payment
row and returns $0.00 for member cost. This is the single easiest mistake to
make against this view.

### Layer 2 — `CODE_DICTIONARY`

Source: [`code_dictionary_raw.sql`](sql/ddl/code_dictionary_raw.sql),
[`code_dictionary_classify.sql`](sql/ddl/code_dictionary_classify.sql)

One row per clinical code seen anywhere in the share — 1,453 of them — built as
a table rather than a view because it is small, it saves rescanning ~356M rows
per lookup, and it can be hand-corrected where a derived classification is wrong.

| Field | Definition | Reasoning |
|---|---|---|
| canonical description | One agreed name per code | The same code appears with several spellings (`Encounter for Problem` / `for problem` / `for problem (procedure)`) |
| `CODE_CATEGORY` | Condition / Procedure / Encounter type / Medication / other | Mostly parsed from the SNOMED semantic tag in the description |
| `IS_CONDITION` | Narrow: a diagnosable condition | The flag for "top conditions by cost". Without it that ranking returns *Full-time employment* and *Medication review due* |
| `IS_CLINICAL` | Wider: condition, procedure or similar | For questions about clinical versus administrative activity |
| `CLASSIFIED_BY` | `semantic_tag` / `provenance` / `manual_override` | Records **how** each row was decided, so any classification can be traced and overridden rather than taken on trust |

### Layer 3 — `V_CLAIMS_TX_WITH_CARETYPE`

Source: [`sql/ddl/v_claims_tx_with_caretype.sql`](sql/ddl/v_claims_tx_with_caretype.sql)

| Field | Definition | Reasoning |
|---|---|---|
| `PRIMARY_CONDITION` | `DIAGNOSIS1` when it is a real condition, else `DIAGNOSIS2` | Only 46.7% of `DIAGNOSIS1` values are a condition; the fallback recovers 5.9M claims |
| `CARE_TYPE` | One of fifteen groups from an ordered rule ladder, defaulting to `No diagnosis on claim` | Conditions are too granular to act on; the default keeps undiagnosed spend visible rather than silently dropping a quarter of the money |
| `FACILITY_ID` | `ENCOUNTERS.ORGANIZATION_ID` | Facility *names* are not unique, and unmatched rows collapse into one blank bucket that ranks near the top |
| `PATIENT_STATE` | `PATIENTS.STATE` | Where the member lives — not the same as `FACILITY_STATE`, where care was delivered |
| `SERVICE_MONTH`, `SERVICE_QUARTER` | Derived from `FROMDATE` | Trend grains below year |

**On the care-type ladder.** Rules are tested in order and the first match wins,
so position is part of the definition. A rule for gallbladder infection must be
tested before the kidney rule, because that rule's keyword `cystitis` is a
substring of `cholecystitis`. Getting that order wrong filed about 1,250
gallbladder patients as kidney disease. The ladder is duplicated across fifteen
files, so a checker compares every copy and fails if any branch, keyword or
position differs.

### Layer 4 — aggregate tables

Source: [`sql/ddl/powerbi_model_build.sql`](sql/ddl/powerbi_model_build.sql)

| Field | Definition | Reasoning |
|---|---|---|
| `MEMBER_PAID_SHARE` | Member paid ÷ **total paid** | Share of what was actually collected, not of what was billed. Billed is the wrong denominator when collection is not 100% |
| `VISITS_PER_MEMBER` | Distinct encounters ÷ distinct patients | Separates a facility that is busy from one where each visit is expensive |
| `BILLED_PER_VISIT` | Billed ÷ distinct encounters | The price side of the same pair |
| `SPEND_RANK` | `ROW_NUMBER()` over billed, descending | Precomputed in SQL; the equivalent DAX is O(n²) and does not finish at 1.26M members |
| `CUMULATIVE_PCT` | Running share of total billed, in rank order | Answers "how few carry half" directly |
| `ENTITIES_FOR_HALF` | First rank where `CUMULATIVE_PCT` ≥ 50 | The headline concentration figure |
| `GRAIN` / `SEGMENT` / `MEMBERS` | Distinct member counts stored per grain | Money sums across categories; people do not. One member appears under several care types, so adding subtotals double-counts them |

---

## Judgment calls

Each of these could reasonably have gone the other way. They are listed so a
reader can disagree with a specific decision rather than the whole result.

- **The `DIAGNOSIS2` fallback** attributes a claim's full cost to a nominally
  *secondary* diagnosis. Both cuts are kept on disk — position-1-only
  (`condition_cost_clean.sql`, $68.17B) and with fallback
  (`condition_cost_with_fallback.sql`, $72.69B) — because it is a trade-off, not
  a strict improvement.
- **`Stress` is classified as a social determinant, not a condition.** Reversible
  with a one-line update to `CODE_DICTIONARY`.
- **Undiagnosed spend is labelled, not dropped.** It is $26.4B, a quarter of the
  total, and members carry a much larger share of it (28.3%) than of diagnosed
  care (17.6%). Dropping it would move the headline member-paid share from 20.4%
  to 17.6% without saying so.
- **Care types are fifteen buckets, not more.** Finer groups would classify more
  precisely and be harder to act on. Cholecystitis sits in `Infections (other)`
  because there is no digestive bucket; adding one would reshuffle other
  conditions too.
- **Concentration tables ignore the slicers.** They describe the whole 2020–2024
  window and do not respond to year or payer filters, because rank and running
  totals are precomputed. Every card built on them says so.

---

## Validation

Every figure reconciles to a fixed anchor before it reaches the report:

| Figure | Value |
|---|---|
| All spend, 2020–2024 | $99,825,019,809 |
| Excluding the admin noise code | $99,111,300,188 |
| Attributable to a clinical condition | $72,685,492,672 |
| Patients with spend | 1,259,375 |
| Claims | 68,645,121 |

A query that does not tie out is wrong until shown otherwise. Several queries
carry their own acceptance check that prints `PASS` or `CHECK`, so a bad run
announces itself rather than looking plausible, and findings were tested more
than one way before being written up — concentration across four separate
groupings, member-paid share re-checked inside each line of business, and the
three headline findings retested against the documented pricing defect.

Bugs found in the analysis itself are recorded alongside the source defects in
[`DATA_QUALITY_LOG.md`](DATA_QUALITY_LOG.md), for the same reason.

---

## Limitations

The data is synthetic. Synthea prices some conditions far above real-world
benchmarks — a normal pregnancy at roughly 8.6× a comparable real figure, with
eleven of the twenty highest-cost conditions carrying a similar gap. Ratios
survive this because scaling a bill and its payment by the same factor cancels
out; absolute dollar figures do not.

Collection is modelled at 100% — no denials, write-offs or A/R aging — so
reimbursement-gap and bad-debt analyses return zero by construction rather than
because performance is perfect. Data ends 9 November 2024, so 2024 totals run
roughly 15% light; ratios are fine, annual totals are not comparable.

Member-paid share is a percentage of the bill, not a measure of hardship. A high
share of a small bill and a high share of a large one are different things.
