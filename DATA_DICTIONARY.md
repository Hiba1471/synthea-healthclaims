# Data Dictionary

Table and column reference for the Synthea claims share and the curated layer
built on top of it.

Companion documents:

- [`METHODOLOGY.md`](METHODOLOGY.md) — cleaning decisions and every engineered
  field, with the reasoning.
- [`DATA_QUALITY_LOG.md`](DATA_QUALITY_LOG.md) — every defect found in the
  source, with evidence and resolution.

---

## Dataset and environment

### Source

**`SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER`** — a Snowflake
share of Synthea-generated synthetic healthcare data. 18 tables, ~2.3B rows.

The share is **read-only**. It cannot be altered, so all corrections live in a
curated layer rather than being fixed at source, so the source data is never
modified.

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
- Data ends **2024-11-09**, so 2024 totals run ~10–15% light. Label
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

## Column reference

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
| `OUTSTANDING_RUNNING_BALANCE` | **renamed deliberately** — see [`DATA_QUALITY_LOG.md`](DATA_QUALITY_LOG.md) §1.1 |
| `PAYER_ID`, `PAYER_NAME`, `PAYER_CITY`, `PAYER_TYPE` | `PAYER_NAME` = the insurer; `PAYER_ID` keys insurer × city |
| `ENCOUNTERCLASS` | care setting |

The three **derived** columns are marked as such — they do not
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
a one-line `UPDATE` — so classification is never taken on trust.
