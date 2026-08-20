-- =====================================================================
-- Q3: HOW CONCENTRATED IS SPEND?
--
-- North star: the top N% of PATIENTS account for X% of spend.
-- Secondary:  the same Pareto for CONDITIONS and ORGANISATIONS.
--             Is spend driven by a few very sick patients, a few expensive
--             conditions, or a few high-volume providers?
--
-- Payers were considered as a fourth grain and rejected: with only 10
-- entities that is market share, not concentration.
--
-- Method: aggregate to entity level ONCE per grain, then window over that
-- small result -- never re-scan the fact table per bucket.
-- Results: sql/results/q3_concentration_2020_2024.csv
-- =====================================================================

WITH base AS (
    SELECT CLAIM_ID, PATIENT_ID, ENCOUNTER_ID, BILLED_AMOUNT
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
    WHERE NOT IS_ADMIN_NOISE_CODE
      AND PROCEDURECODE IS NOT NULL
      AND BILLED_AMOUNT > 0
),

-- ---- grain 1: patients -------------------------------------------------
patient_totals AS (
    SELECT 'Patients' AS grain, PATIENT_ID AS entity, SUM(BILLED_AMOUNT) AS amt
    FROM base GROUP BY PATIENT_ID
),

-- ---- grain 2: conditions (same dx1 -> dx2 fallback as Q1) ---------------
claim_condition AS (
    SELECT
        c.CLAIM_ID,
        CASE WHEN d1.IS_CONDITION THEN c.DIAGNOSIS1
             WHEN d2.IS_CONDITION THEN c.DIAGNOSIS2 END AS condition_code
    FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.CLAIMS c
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d1 ON c.DIAGNOSIS1 = d1.CODE
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d2 ON c.DIAGNOSIS2 = d2.CODE
),
condition_totals AS (
    SELECT 'Conditions' AS grain, cc.condition_code AS entity, SUM(b.BILLED_AMOUNT) AS amt
    FROM base b
    JOIN claim_condition cc ON b.CLAIM_ID = cc.CLAIM_ID
    WHERE cc.condition_code IS NOT NULL
    GROUP BY cc.condition_code
),

-- ---- grain 3: organisations (view lacks ORG, so join ENCOUNTERS) --------
org_totals AS (
    SELECT 'Organisations' AS grain, e.ORGANIZATION_ID AS entity, SUM(b.BILLED_AMOUNT) AS amt
    FROM base b
    JOIN SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.ENCOUNTERS e
      ON b.ENCOUNTER_ID = e.ENCOUNTER_ID
    GROUP BY e.ORGANIZATION_ID
),

stacked AS (
    SELECT * FROM patient_totals
    UNION ALL SELECT * FROM condition_totals
    UNION ALL SELECT * FROM org_totals
),
ranked AS (
    SELECT
        grain,
        amt,
        ROW_NUMBER() OVER (PARTITION BY grain ORDER BY amt DESC)      AS rn,
        COUNT(*)    OVER (PARTITION BY grain)                         AS n_entities,
        SUM(amt)    OVER (PARTITION BY grain)                         AS grain_total,
        SUM(amt)    OVER (PARTITION BY grain ORDER BY amt DESC
                          ROWS BETWEEN UNBOUNDED PRECEDING
                                   AND CURRENT ROW)                   AS cum_amt
    FROM stacked
),
scored AS (
    SELECT grain, n_entities, grain_total,
           rn / n_entities        AS entity_pctile,
           cum_amt / grain_total  AS cum_share
    FROM ranked
)
SELECT
    grain                                                    AS "Ranked by",
    n_entities                                               AS "How many exist",
    ROUND(grain_total)                                       AS "Total spend",

    -- "the priciest 1% of them run up X% of the bill"
    ROUND(100 * MAX(CASE WHEN entity_pctile <= 0.01 THEN cum_share END), 1)
        AS "Priciest 1% run up this % of spend",
    ROUND(100 * MAX(CASE WHEN entity_pctile <= 0.05 THEN cum_share END), 1)
        AS "Priciest 5% run up this % of spend",
    ROUND(100 * MAX(CASE WHEN entity_pctile <= 0.10 THEN cum_share END), 1)
        AS "Priciest 10% run up this % of spend",
    ROUND(100 * MAX(CASE WHEN entity_pctile <= 0.20 THEN cum_share END), 1)
        AS "Priciest 20% run up this % of spend",
    ROUND(100 * MAX(CASE WHEN entity_pctile <= 0.50 THEN cum_share END), 1)
        AS "Priciest 50% run up this % of spend",

    -- same data flipped: how few does it take to reach half / most of the money
    ROUND(100 * MIN(CASE WHEN cum_share >= 0.50 THEN entity_pctile END), 2)
        AS "% of them needed to reach half the spend",
    ROUND(n_entities * MIN(CASE WHEN cum_share >= 0.50 THEN entity_pctile END))
        AS "= this many of them",
    ROUND(100 * MIN(CASE WHEN cum_share >= 0.80 THEN entity_pctile END), 2)
        AS "% of them needed to reach 80% of spend",
    ROUND(n_entities * MIN(CASE WHEN cum_share >= 0.80 THEN entity_pctile END))
        AS "= this many of them "
FROM scored
GROUP BY grain, n_entities, grain_total
ORDER BY CASE grain WHEN 'Patients' THEN 1 WHEN 'Conditions' THEN 2 ELSE 3 END;
