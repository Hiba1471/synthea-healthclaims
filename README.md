# Calder Health: Five-Year Claims Analysis

An end-to-end healthcare claims analysis — a corrected data layer over a raw
Snowflake share, 47 analysis queries, a Power BI model, and a client-facing
report on where spending concentrates and who carries the cost.

**[Read the report →](https://hiba1471.github.io/synthea-healthclaims/dashboard/analysis_report.html)**

## Overview

Calder Health is a non-profit health plan in Cleveland serving 1.26 million
members across 3,918 facilities, running two lines of business: commercial
employer plans with a deductible and coinsurance, and government Medicaid and
Medicare plans with a flat copay per visit. Before setting benefits and
negotiating networks, it wanted to know where five years of spending went and
who actually paid for it.

The analysis is built around three business questions:

- **Where did the money go** — which conditions and types of care drive spending,
  and is that concentrated enough to act on?
- **Who bore it** — how much of each bill members pay themselves, and whether
  that differs between commercial and government plans.
- **Where does it concentrate** — whether spending pools in a few facilities and
  places, or spreads evenly across the network.

Member-paid share is treated as a headline metric rather than an appendix,
because the plan measures affordability by what a member actually pays rather
than by what the plan spends.

*Calder Health is an illustrative client — the questions needed someone to have
asked them. The analysis behind every figure is real and reproducible.*

## Data

Claims come from a read-only Snowflake share,
`SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER`, holding Synthea-generated
synthetic records: 887 million claim transactions across 124 million claims and
1.4 million simulated patients. Five tables are used — claim transactions,
claims, encounters, organizations and patients.

All figures cover **1 January 2020 to 31 December 2024**, five complete years:
68.6 million claims, 1,259,375 patients and $99.11 billion billed. The window
matters, because unfiltered the source spans simulated history back to 1914 and
volume steps up roughly eightfold in November 2019, so cumulative totals across
the full span are not business figures.

## Data cleaning

The share is read-only, so nothing could be fixed at source. Everything reads
through a curated view instead —
[`sql/ddl/v_claims_tx_clean.sql`](sql/ddl/v_claims_tx_clean.sql) — which is the
correction layer. The defects it neutralises are not missing values or bad
formatting; they are columns that answer a different question than their name
suggests, so a wrong result looks completely reasonable.

Three examples of what that meant in practice.

**Uncollected revenue that wasn't.** `SUM(OUTSTANDING)` came to $45.3 billion,
which would be a catastrophic unpaid balance. I checked it a second way —
billed minus paid on each claim — and got roughly zero. Two answers five orders
of magnitude apart meant one of them was measuring something else. `OUTSTANDING`
turns out to be stamped on every row as money moves through charge, transfer and
payment, so summing it counts the same balance again at every stage. True
uncollected revenue is $83,363. I renamed the column `OUTSTANDING_RUNNING_BALANCE`
rather than dropping it, because hiding it would send the next person back to the
raw table with no warning, whereas a name that says "running balance" makes
`SUM()` visibly wrong at the point of writing it.

**Payments credited to the wrong party.** `PAYER_ID` looked like it identified
who paid. Tracing one claim through its transfer chain showed responsibility
shifting to the patient, who then paid directly — while the claim still carried
the insurer's id. The field records who was *billed*. The real signal is
`METHOD` on payment rows: `ECHECK` is the insurer, everything else is the member
paying out of pocket. Without that distinction $20.3 billion of member payments
are credited to insurers, and the entire question of what members pay cannot be
asked at all.

**A diagnosis field that mostly isn't.** A first pass at "top conditions by cost"
returned *Full-time employment* and *Medication review due* in its top twelve.
Testing `DIAGNOSIS1` against the encounter record explained it: about two thirds
of its values are copied encounter metadata, and only 46.7% are a real condition.
The convention is inverted — `DIAGNOSIS2` onward are progressively cleaner. I
built a [code dictionary](sql/ddl/code_dictionary_classify.sql) flagging which
codes are genuine conditions, then took `DIAGNOSIS1` when it qualified and fell
back to `DIAGNOSIS2` when it did not, recovering 5.9 million claims. Both cuts
are kept on disk, because the fallback attributes a claim's full cost to a
nominally secondary diagnosis — a real trade-off, not a strict improvement.

The same pattern covers the rest: `AMOUNT` populated on transfer rows as well as
charges (double-counting $23.4B), 120 payer rows for 10 insurers keyed by
insurer-*city* pair, and claim counts that sum to exactly twice the true figure
across procedure rows.

Every defect, how it was found, what it cost and how it was resolved is recorded
in [`DATA_QUALITY_LOG.md`](DATA_QUALITY_LOG.md) — including a section on bugs in
my own analysis, kept for the same reason.

## Methodology

**Care-type classification** —
[`q2_patient_cost_by_care_type.sql`](sql/analysis/q2_patient_cost_by_care_type.sql)
holds the reference copy of an ordered rule ladder that maps each condition
description into one of fifteen care types. Order is load-bearing: the first
matching rule wins, so a rule for gallbladder infection has to be tested before
the kidney rule, whose keyword is a substring of it. The ladder is duplicated
across fifteen files, so a checker compares every copy and fails if any branch,
keyword or position drifts.

**Aggregation** — ten pre-aggregated tables sized for import, with rankings and
cumulative distributions computed in SQL as window functions rather than in DAX,
which does not complete at 1.26 million rows.

**Modeling** — a Power BI star schema: one fact table, four dimensions, all
one-to-many and single-direction. Distinct member counts are stored separately at
five grains, because counts of people do not sum across categories the way money
does.

Every figure was reconciled against fixed anchors — $99,111,300,188 billed,
1,259,375 patients, 68.6 million claims — before reaching the report, and several
queries carry their own acceptance checks that print `PASS` or `CHECK`.

## Key findings

Diagnosed spending is severely top-heavy: twenty conditions carry 91% of it, and
just two of fifteen care types account for half. Member cost burden splits
sharply along plan design: across the ten conditions where members carry the most,
**commercial members pay more on every one**, by between 12.9 and 78.1 percentage
points — obesity runs 86.8% against 8.7%. The two populations barely overlap, which
points at benefit design rather than clinical mix. That
share is also highest on the cheapest, most routine care, so the conditions where
members pay the largest *percentage* and the largest *dollars* are different
lists: lung cancer bills $3.4B and leaves the member 5.4%, while normal pregnancy
bills $28.9B and leaves them 17.0%. Spending concentrates in places far more than
in people — **86 of 3,918 facilities** carry half of all spending, against 134,198
members for the same half — and the expensive facilities are not overcharging;
repricing every procedure to a common rate shows the spread is case mix, not
price.

Full findings, charts and recommendations are in the report.

## Repository structure

| Path | Description |
|---|---|
| `dashboard/analysis_report.html` | Client-facing report: findings, charts and recommendations. |
| `sql/ddl/` | Curated views, the code dictionary, and the ten aggregate tables. |
| `sql/analysis/` | 47 standalone analysis queries, one per question. |
| `sql/results/` | Query output as CSV, linked from the report. |
| `powerbi/` | DAX measures, the data model diagram, and dashboard documentation. |
| `DATA_ANALYSIS_CONTEXT.md` | Full table and column reference for the source share. |
| `DATA_QUALITY_LOG.md` | Every data defect found, with evidence. |

To rebuild the curated objects, run in order:

```bash
snow sql -f sql/ddl/v_claims_tx_clean.sql
snow sql -f sql/ddl/code_dictionary_raw.sql
snow sql -f sql/ddl/code_dictionary_classify.sql
snow sql -f sql/ddl/v_claims_tx_with_caretype.sql
snow sql -f sql/ddl/powerbi_model_build.sql
```

## Tools

- **Snowflake + SQL** — the correction layer, analysis queries and aggregate
  tables. Queries were written with Claude Code and run through the Snowflake CLI
  (`snow sql`) rather than the web UI, which kept each one in a versioned `.sql`
  file. I validated every output against the anchors above and read the query
  logic for correctness before any result reached the report.
- **Power BI + DAX** — a three-page dashboard on the star schema.
- **HTML + CSS + SVG** — the final client deliverable, self-contained and served
  through GitHub Pages.

## Limitations

The data is synthetic, and Synthea prices some conditions far above real-world
benchmarks — a normal pregnancy at roughly 8.6× a comparable real figure, with
eleven of the twenty highest-cost conditions carrying a similar documented gap.
Ratios survive this, because scaling a bill and its payment by the same factor
cancels out; absolute dollar figures do not. The report tests its three headline
findings against that defect in an appendix rather than assuming they hold.

The dataset also models 100% collection — no denials, write-offs or A/R aging —
so reimbursement-gap and bad-debt analyses return zero by construction, not
because performance is perfect. Data ends 9 November 2024, so 2024 totals run
roughly 15% light. Member-paid share is a percentage of the bill, not a measure
of hardship. Full detail is in `DATA_QUALITY_LOG.md`.
