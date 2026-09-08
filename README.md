# Healthcare claims analysis — Snowflake

Analysis of the Snowflake share
`SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER` (Synthea synthetic
data: 887M claim transactions, 124M claims, 1.4M patients).

> **`SYNTHEA_HEALTHCLAIMS` is not a data source.** `.env` points at that
> database, but its `PUBLIC` schema was empty — it exists here purely to host
> the curated objects below. All source data lives in the read-only share.
> `.env` also carries Gemini and EIA (energy) API keys left over from earlier
> work; no energy data is used in this project.

---

## Tech stack

| Layer | What | Where |
|---|---|---|
| Source | Snowflake share `SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER` — read-only, 887M claim transactions | — |
| Correction layer | Snowflake SQL views + a code dictionary table, in `SYNTHEA_HEALTHCLAIMS.PUBLIC` | `sql/ddl/v_claims_tx_clean.sql`, `code_dictionary_*.sql` |
| Care-type layer | View adding care type, primary condition, facility and member attributes | `sql/ddl/v_claims_tx_with_caretype.sql` |
| Aggregates | 10 pre-aggregated tables sized for import — facts, dimensions, concentration curves | `sql/ddl/powerbi_model_build.sql` |
| Analysis | ~50 standalone analysis queries, one per question | `sql/analysis/` |
| BI | Power BI Desktop — Import mode, star schema, 3 pages | — |
| Measures | DAX | `powerbi/measures.dax` |
| Charts & report | Python 3.12 (pandas, matplotlib) generating hand-authored HTML/CSS/SVG | `dashboard/generators/` |
| Guardrail | Python script checking the care-type ladder stays identical in all 3 copies | `tools/check_care_type_ladder.py` |

Data flows one way: **share → curated views → aggregate tables → Power BI import → DAX → visuals.** No transformation happens in Power BI; anything that could be pushed into SQL was.

---

## Power BI dashboard

Answers: *where does healthcare spending concentrate by care type, and how does member cost burden vary by payer type?*

Build the model with one file:

```bash
snow sql -f sql/ddl/powerbi_model_build.sql
```

It creates 10 tables, each with a short comment saying what it aggregates and which visuals it feeds, and ends with an acceptance check — every row must read `PASS` before you refresh Power BI. **These are tables, not views**; they go stale silently, so re-run the whole file after any change to `V_CLAIMS_TX_WITH_CARETYPE`.

The dashboard itself — pages, visuals, model relationships, formatting gotchas and the figures every visual must reconcile to — is documented in **[`powerbi/README.md`](powerbi/README.md)**.

The earlier `v_agg_*.sql` and `v_dim_*.sql` files in `sql/ddl/` are superseded by this one and are kept only for history.

---

## The report

`dashboard/analysis_report.html` is the client-facing write-up — client
background, north-star metrics, executive summary, and five findings each with
its figures, captions and what was examined. It is assembled from the charts in
`dashboard/`, so rebuild those first if their data changes, then run:

```bash
python3 dashboard/generators/analysis_report.py
```

To serve it: enable GitHub Pages on this repo (Settings → Pages → deploy from
branch, root). It will then be at
`https://<user>.github.io/<repo>/dashboard/analysis_report.html`. Without Pages,
clicking the file in GitHub shows its source rather than the rendered page.

**The client, Calder Health, is invented** — the questions needed someone to
have asked them. The analysis behind every figure is real and reproducible.

---

## Quick start

Everything reads through two curated objects rather than the raw share. Query
those, not the source tables — the source has traps that produce confidently
wrong answers (see [Gotchas](#gotchas)).

```bash
snow sql -q "SELECT PAYER_TYPE, SUM(PAID_BY_PAYER), SUM(PAID_BY_PATIENT) FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN GROUP BY 1"
```

| Object | Kind | Purpose |
|---|---|---|
| `SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN` | view | Claim transactions with correct money columns, payer collapsed, date window applied |
| `SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY` | table (1,453 rows) | Every clinical code → one canonical name + category. 100% resolution on all 9 code fields |

The share is **read-only** (an imported Snowflake share), so nothing can be
fixed at source. These objects are the correction layer.

---

## Layout

```
sql/
  ddl/                              curated objects -- run in this order
    v_claims_tx_clean.sql           the base view
    code_dictionary_raw.sql         pass 1: gather codes from 11 sources
    code_dictionary_classify.sql    pass 2: classify them
    v_claims_tx_with_caretype.sql   adds care type, condition, facility
    powerbi_model_build.sql         all 10 aggregate tables, one file
  analysis/                         one query per analysis question
  snowflake_queries.sql             analysis query history, chronological
  condition_cost_clean.sql          condition costs, DIAGNOSIS1 only
  condition_cost_with_fallback.sql  condition costs, with DIAGNOSIS2 fallback
  results/                          output CSVs -- see results/README.md
powerbi/
  measures.dax                      every DAX measure in the model
dashboard/
  analysis_report.html              the client-facing write-up
  generators/                       Python scripts that build the HTML charts
tools/
  check_care_type_ladder.py         guards the 3 copies of the care-type ladder
```

### Rebuilding the curated objects

Order matters — `classify` alters the table `raw` creates.

```bash
snow sql -f sql/ddl/v_claims_tx_clean.sql
snow sql -f sql/ddl/code_dictionary_raw.sql
snow sql -f sql/ddl/code_dictionary_classify.sql
snow sql -f sql/ddl/v_claims_tx_with_caretype.sql
snow sql -f sql/ddl/powerbi_model_build.sql
```

`code_dictionary_raw.sql` scans ~1.3B rows across 11 tables (two columns each)
and takes a few minutes. The view is free to create. To re-run only the
classification after editing rules, skip the `ALTER TABLE` at the top of
`classify` and run from the first `UPDATE` onward.

---

## Standing scope

All CLAIMS_TX analysis is windowed to **`FROMDATE` 2020-01-01 → 2024-12-31**,
baked into the view. Two reasons:

- Unfiltered, the table spans **1914–2024** (~110 years of simulated history),
  so cumulative totals are not business figures.
- Volume steps up **~8x in Nov 2019** (~$200M/month → ~$1.7B/month), so
  calendar-2019 blends two population regimes and is not comparable to 2020+.

Data ends **2024-11-09**, so 2024 totals run ~15% light. Ratios are fine;
absolute annual totals are not.

To change the window, edit the two predicates at the bottom of
`sql/ddl/v_claims_tx_clean.sql` — it is the single place scope is defined.

---

## Gotchas

Each of these produces a plausible-looking wrong answer if you query the raw
share directly. The curated objects neutralise all of them.

| # | Trap | Consequence |
|---|---|---|
| 1 | `OUTSTANDING` is a **mid-flow running balance**, not terminal A/R | `SUM()` returns **$45.3B**; true uncollected is **$83K**. Overstates by ~543,000x |
| 2 | `AMOUNT` is populated on `TRANSFERIN` rows too, not just `CHARGE` | Naive sums double-count $23.4B of transferred balances |
| 3 | `encounters.PAYER_ID` = who was **billed**, not who **paid** | Misattributes $20.3B of patient payments to insurers. Use `METHOD` on PAYMENT rows: `ECHECK` = insurer, else patient |
| 4 | `DIAGNOSIS1` mixes code systems | 18.4% of its uses are procedure codes; ~65% is copied encounter metadata. Only 46.7% is a real condition |
| 5 | `PAYERS` has 120 rows for **10 insurers** (12 city variants each) | `PAYER_ID` keys an insurer-*city* pair. Group by `PAYER_NAME` for the insurer, `PAYER_CITY` for the region |
| 6 | Claim counts are **not additive** across procedure rows | Sums to 249M against 124M actual claims — exactly 2.0x |

### What this dataset cannot answer

The data models **100% collection** — no denials, write-offs, contractual
adjustments or A/R aging. 98.7% of claims are paid the same day they are
charged. Reimbursement-gap, bad-debt and days-in-A/R analyses all return zero
**by construction**, not because performance is perfect. Report that as a
finding; do not present the zeros as a result.

---

## Headline result

Which conditions cost most, and is that concentrated by payer?
(`sql/results/condition_cost_with_fallback_2020_2024.csv`)

$72.69B across 33.6M claims and 185 conditions, led by Normal pregnancy
($28.9B, 39.8%), Allergy to substance ($8.6B) and Gingivitis ($8.5B). Cancer is
78–88% government-funded; pregnancy and contraception tilt commercial. A dental
cluster of ~$10.5B is only visible with the DIAGNOSIS2 fallback applied.

Two judgment calls are baked into that number and should be stated wherever it
is used:

1. **DIAGNOSIS2 fallback** — take `DIAGNOSIS1` when it is a real condition,
   else fall back to `DIAGNOSIS2`. Recovers 5.9M claims, but attributes a
   claim's full cost to a nominally *secondary* diagnosis. The conservative
   DIAGNOSIS1-only cut is `condition_cost_by_payer_2020_2024.csv` ($68.17B).
2. **`Stress` classified as a social determinant**, not a condition. Reversible
   with a one-line `UPDATE` to `CODE_DICTIONARY`.

Classification generally is auditable: `CODE_DICTIONARY.CLASSIFIED_BY` records
whether each code was decided by SNOMED semantic tag, by provenance, or by
hand, so any row can be traced and overridden.

---

## Credentials

`.env` holds Snowflake credentials plus Gemini / EIA API keys and a Slack
webhook, **in plaintext**. It is listed in `.gitignore`, which was added in the
first commit, and `git log --all -- .env` returns nothing — it has never been
committed. Re-check that before pushing this repository anywhere.

The keys are still plaintext on disk, so consider rotating them: a webhook URL
and an API key are usable by anyone who obtains the file.

The Snowflake CLI connection used here is `conn` (`snow connection list`).
