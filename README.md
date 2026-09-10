# Calder Health: Five-Year Claims Analysis

An end-to-end healthcare claims analysis: a corrected data layer over a raw
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

The analysis covers **1 January 2020 to 31 December 2024**: 68.6 million claims,
1,259,375 patients and $99.11 billion billed.

The analysis is built around three business questions:

- **Where did the money go?** Which conditions and types of care drive spending,
  and is that concentrated enough to act on?
- **Who bore it?** How much of each bill members pay themselves, and whether
  that differs between commercial and government plans.
- **Where does it concentrate?** Whether spending pools in a few facilities and
  places, or spreads evenly across the network.

Member-paid share is treated as a headline metric rather than an appendix,
because the plan measures affordability by what a member actually pays rather
than by what the plan spends.

*Calder Health is an illustrative client. The questions needed someone to have
asked them. The analysis behind every figure is real and reproducible.*

## Data

Claims come from a read-only Snowflake share,
`SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER`, holding Synthea-generated
synthetic records: 887 million claim transactions across 124 million claims and
1.4 million simulated patients. Five tables are used: claim transactions,
claims, encounters, organizations and patients.

Table and column definitions, the standing analysis window and the reference
totals every figure reconciles to are in
[`DATA_DICTIONARY.md`](DATA_DICTIONARY.md).

## Data cleaning / Methodology

The share is read-only, so nothing could be fixed at source; every query reads
through a curated view that acts as the correction layer. The defects it
neutralises are not missing values or bad formatting. They are columns that
answer a different question than their name suggests, so a wrong result looks
entirely reasonable and nothing errors. `SUM(OUTSTANDING)` reads as $45.3 billion
of unpaid balances when the true figure is $83,363; `PAYER_ID` records who was
*billed* rather than who paid, misattributing $20.3B of member payments; only
46.7% of `DIAGNOSIS1` values are a real condition. Each was caught by measuring
the same quantity a second way and treating a disagreement as proof one measure
was wrong. On top of the cleaned data sit the derived fields the analysis
actually uses: plan type, care type, primary condition, and the per-facility
rates behind the concentration work.

**Full detail:** [`METHODOLOGY.md`](METHODOLOGY.md) covers every cleaning
decision, each derived field with its reasoning, and the judgment calls that
could reasonably have gone the other way.
[`DATA_QUALITY_LOG.md`](DATA_QUALITY_LOG.md) records every defect with evidence.

## Key findings

Diagnosed spending is severely top-heavy: twenty conditions carry 91% of it, and
just two of fifteen care types account for half. Member cost burden splits
sharply along plan design: across the ten conditions where members carry the most,
**commercial members pay more on every one**, by between 12.9 and 78.1 percentage
points. Obesity runs 86.8% against 8.7%. The two populations barely overlap, which
points at benefit design rather than clinical mix. That
share is also highest on the cheapest, most routine care, so the conditions where
members pay the largest *percentage* and the largest *dollars* are different
lists: lung cancer bills $3.4B and leaves the member 5.4%, while normal pregnancy
bills $28.9B and leaves them 17.0%. Spending concentrates in places far more than
in people: **86 of 3,918 facilities** carry half of all spending, against 134,198
members for the same half. The expensive facilities are not overcharging;
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
| `METHODOLOGY.md` | Cleaning decisions and every engineered field, with the reasoning. |
| `DATA_DICTIONARY.md` | Table and column reference for the share and the curated layer. |
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

- **Snowflake + SQL**: the correction layer, analysis queries and aggregate
  tables. Queries were written with Claude Code and run through the Snowflake CLI
  (`snow sql`) rather than the web UI, which kept each one in a versioned `.sql`
  file. I validated every output against the anchors above and read the query
  logic for correctness before any result reached the report.
- **Power BI + DAX**: a three-page dashboard, modeled with the star schema.
- **HTML + CSS**: the final client deliverable, Claude helped with designing the HTML report which is self-contained and served
  through GitHub Pages.

## Limitations

The data is synthetic, and Synthea prices some conditions far above real-world
benchmarks. A normal pregnancy runs roughly 8.6× a comparable real figure, with
eleven of the twenty highest-cost conditions carrying a similar documented gap.
Ratios survive this, because scaling a bill and its payment by the same factor
cancels out; absolute dollar figures do not. The report tests its three headline
findings against that defect in an appendix rather than assuming they hold.

The dataset also models 100% collection, with no denials, write-offs or A/R
aging, so reimbursement-gap and bad-debt analyses return zero by construction, not
because performance is perfect. Data ends 9 November 2024, so 2024 totals run
roughly 15% light. Member-paid share is a percentage of the bill, not a measure
of hardship. Full detail is in `DATA_QUALITY_LOG.md`.
