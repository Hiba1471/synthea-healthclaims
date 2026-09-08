-- =====================================================================
-- SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
--
-- Transaction-line grain, enriched with care type, facility and patient
-- state, for the Power BI report. Sits on top of V_CLAIMS_TX_CLEAN, which
-- already applies the standing 2020-2024 window and the money-column fixes.
--
-- SCOPE MUST MATCH THE ANALYSIS. The predicate below is the same one every
-- query in sql/analysis/ uses:
--
--     WHERE NOT IS_ADMIN_NOISE_CODE AND PROCEDURECODE IS NOT NULL
--
-- Do NOT add "AND BILLED_AMOUNT > 0". BILLED_AMOUNT is
-- IFF(TYPE = 'CHARGE', AMOUNT, 0), so that predicate keeps CHARGE rows and
-- drops every PAYMENT row -- and PAID_BY_PATIENT / PAID_BY_PAYER are non-zero
-- ONLY on PAYMENT rows. The result is a report where billed is correct and
-- every paid column is exactly zero. That is what this view returned before
-- 2026-09-03, and it is the reason this comment exists.
--
-- A transaction line is a CHARGE or a PAYMENT, never both. Any measure over
-- this view must therefore aggregate across lines -- SUM(BILLED_AMOUNT) and
-- SUM(PAID_BY_PATIENT) are both correct over a group of rows, but no single
-- row carries both. Do not expect them to be non-zero on the same line.
--
-- CONDITION ATTRIBUTION is claim-level, via CLAIMS.DIAGNOSIS1 / DIAGNOSIS2
-- resolved through CODE_DICTIONARY, exactly as q2_patient_cost_by_care_type.sql
-- does it. An earlier version joined CONDITIONS on PATIENT_ID plus a
-- same-year date range and took MAX(DESCRIPTION), which returns whichever of
-- the patient's conditions sorts last alphabetically that year rather than the
-- condition the claim is actually for. It also scanned CONDITIONS against every
-- transaction line, which is far more expensive than joining at claim grain.
--
-- The CASE ladder is the full ladder from q2_patient_cost_by_care_type.sql,
-- not an abbreviation of it. Order matters: dental is tested first so
-- "infection of tooth" groups as dental rather than as an infection. If that
-- query's ladder changes, change this one with it, or the Power BI care-type
-- splits stop matching the report and the dashboard.
-- =====================================================================

CREATE OR REPLACE VIEW SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE AS
WITH claim_condition AS (
    -- one row per claim: the first diagnosis field that resolves to a real
    -- clinical condition (some DIAGNOSIS1 values are visit types or admin codes)
    SELECT
        c.CLAIM_ID,
        CASE WHEN d1.IS_CONDITION THEN c.DIAGNOSIS1
             WHEN d2.IS_CONDITION THEN c.DIAGNOSIS2
        END AS condition_code
    FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.CLAIMS c
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d1 ON c.DIAGNOSIS1 = d1.CODE
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d2 ON c.DIAGNOSIS2 = d2.CODE
),
classified AS (
    SELECT
        cc.CLAIM_ID,
        d.DESCRIPTION AS primary_condition_name,
        CASE
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(gingiv|dental|tooth|teeth|molar|jaw|palatinus|temporomandibular|mandible|alveolitis).*'
                THEN 'Dental & oral'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(pregnan|miscarriage|ovum|tubal|newborn|antenatal|postnatal).*'
                THEN 'Maternity'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(malignant|carcinoma|neoplasm|polyp of colon).*'
                THEN 'Cancer & tumours'
            -- "cholecystitis" contains the substring "cystitis", so the Kidney &
            -- urinary branch below would otherwise claim a gallbladder infection.
            -- Tested first and routed where it belongs. A word boundary would be
            -- the tidier fix, but \\b support varies by regex engine and this
            -- ladder has to behave identically in Snowflake and in Python.
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*cholecystitis.*'
                THEN 'Infections (other)'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(kidney|renal|cystitis|pyelonephritis|urinary|bladder).*'
                THEN 'Kidney & urinary'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(heart|stroke|myocardial|atrial|aortic|coronary|hypertension|cardiac|circulat).*'
                THEN 'Heart & circulation'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(bronchitis|covid|pharyngitis|sinusitis|sore throat|emphysema|asthma|otitis|respiratory|pneumon|influenza).*'
                THEN 'Respiratory & ENT'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(diabet|obesity|lipid|glycemia|metabolic|triglyceride|osteoporosis|body mass).*'
                THEN 'Diabetes & metabolic'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(drug|alcohol|anxiety|attention deficit|sleep|suicide|overdose|depress|stress).*'
                THEN 'Mental health & substance use'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(injury|fracture|sprain|laceration|burn|concussion|rupture|dislocation|wound).*'
                THEN 'Injury & trauma'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*allerg.*'
                THEN 'Allergy & immune'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(seizure|alzheimer|neuropathy|epilep|dementia).*'
                THEN 'Brain & nervous system'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(sepsis|immunodeficiency|appendicitis|cholecystitis|infection|infective|viral|bacterial).*'
                THEN 'Infections (other)'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*(anemia|anaemia).*'
                THEN 'Blood disorders'
            WHEN LOWER(d.DESCRIPTION) REGEXP '.*pain.*'
                THEN 'Chronic pain'
            ELSE 'Other'
        END AS care_type
    FROM claim_condition cc
    JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d ON cc.condition_code = d.CODE
    WHERE cc.condition_code IS NOT NULL
)
SELECT
    -- ---- keys -------------------------------------------------------
    tx.CLAIMS_TX_ID,
    tx.CLAIM_ID,
    tx.PATIENT_ID,
    tx.ENCOUNTER_ID,

    -- ---- money (see the header: CHARGE rows and PAYMENT rows are
    --      different rows, so these are never both non-zero at once) ---
    tx.BILLED_AMOUNT,
    tx.PAID_AMOUNT,
    tx.PAID_BY_PAYER,
    tx.PAID_BY_PATIENT,

    -- ---- payer ------------------------------------------------------
    tx.PAYER_NAME,
    tx.PAYER_TYPE,

    -- ---- dates, pre-cut for Power BI --------------------------------
    tx.FROMDATE,
    tx.SERVICE_YEAR,
    MONTH(tx.FROMDATE)                    AS SERVICE_MONTH,
    DATE_TRUNC('MONTH', tx.FROMDATE)      AS SERVICE_MONTH_START,
    QUARTER(tx.FROMDATE)                  AS SERVICE_QUARTER,

    -- ---- clinical context -------------------------------------------
    tx.PROCEDURECODE,
    tx.ENCOUNTERCLASS,
    enc.ENCOUNTER_START,
    c.primary_condition_name              AS PRIMARY_CONDITION,
    COALESCE(c.care_type, 'No diagnosis on claim') AS CARE_TYPE,

    -- ---- geography ---------------------------------------------------
    pat.STATE                             AS PATIENT_STATE,
    -- FACILITY_ID is the grouping key for anything counting facilities.
    -- q3_concentration.sql groups by ENCOUNTERS.ORGANIZATION_ID, so a
    -- concentration measure must group by this, NOT by FACILITY_NAME: names
    -- are not guaranteed unique across sites, and an unmatched org would
    -- collapse into a single blank bucket that distorts the ranking.
    enc.ORGANIZATION_ID                   AS FACILITY_ID,
    org.NAME                              AS FACILITY_NAME,
    org.CITY                              AS FACILITY_CITY,
    org.STATE                             AS FACILITY_STATE

FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN tx
LEFT JOIN classified c
    ON tx.CLAIM_ID = c.CLAIM_ID
LEFT JOIN SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.ENCOUNTERS enc
    ON tx.ENCOUNTER_ID = enc.ENCOUNTER_ID
LEFT JOIN SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.PATIENTS pat
    ON tx.PATIENT_ID = pat.PATIENT_ID
LEFT JOIN SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.ORGANIZATIONS org
    ON enc.ORGANIZATION_ID = org.ORGANIZATION_ID
WHERE NOT tx.IS_ADMIN_NOISE_CODE
  AND tx.PROCEDURECODE IS NOT NULL;


-- =====================================================================
-- ACCEPTANCE CHECK. Run this straight after creating the view. It must
-- reproduce sql/results/q2_who_pays_by_year_2020_2024.csv, cut '1. Overall'.
-- Expected, to the dollar:
--
--   2020  billed 20,616,260,845   member paid 4,210,202,568   20.4%
--   2021  billed 20,948,177,114   member paid 4,335,321,688   20.7%
--   2022  billed 20,291,316,213   member paid 4,142,352,401   20.4%
--   2023  billed 20,441,952,993   member paid   ...           20.x%
--   2024  billed 16,813,593,023   member paid   ...           20.x%
--
-- If the member-paid column comes back 0.00, the BILLED_AMOUNT > 0 predicate
-- is back in the view. That is the only thing that produces exactly zero.
-- =====================================================================

SELECT
    SERVICE_YEAR,
    ROUND(SUM(BILLED_AMOUNT))                                        AS TOTAL_BILLED,
    ROUND(SUM(PAID_BY_PATIENT))                                      AS TOTAL_MEMBER_PAID,
    ROUND(100 * SUM(PAID_BY_PATIENT)
          / NULLIF(SUM(PAID_BY_PAYER) + SUM(PAID_BY_PATIENT), 0), 1) AS MEMBER_PAID_SHARE_PCT,
    COUNT(*)                                                         AS ROW_COUNT
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
GROUP BY SERVICE_YEAR
ORDER BY SERVICE_YEAR;
