-- =====================================================================
-- Q3: Lorenz curve coordinates -- the 100 points per grain that draw the
--     concentration curves in dashboard/concentration.html.
--
-- Same computation as q3_concentration.sql, which reports six milestones off
-- the curve (top 1%, 5%, 10%, 20%, the point reaching half, the point reaching
-- 80%). This keeps all 100 steps instead, for plotting.
--
-- Each row reads: rank this grain most-expensive-first, walk down the list to
-- the Nth percentile, and this much of the grain's spend has been covered.
-- Conditions row 1 is Normal pregnancy alone at 39.81%.
--
-- WRITTEN 2026-08-29 TO REPLACE A MISSING QUERY. The result file predates the
-- rule that every CSV keeps its query, so its numbers could not be checked or
-- rebuilt. This reproduces them; see the verification note at the bottom.
--
-- THE THREE CURVES DO NOT SHARE A DENOMINATOR, and the chart must keep saying
-- so. Patients and organisations are shares of all $99.11B of non-admin spend;
-- conditions are a share of only the $72.69B carrying a diagnosis, because a
-- claim with no condition on it cannot be ranked under one. Care types are
-- deliberately absent: the top care type is 99.7% one condition, so that curve
-- would trace the conditions curve.
--
-- Results: sql/results/q3_lorenz_points_2020_2024.csv
-- =====================================================================

WITH base AS (
    SELECT CLAIM_ID, PATIENT_ID, ENCOUNTER_ID, BILLED_AMOUNT
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
    WHERE NOT IS_ADMIN_NOISE_CODE
      AND PROCEDURECODE IS NOT NULL
      AND BILLED_AMOUNT > 0
),
patient_totals AS (
    SELECT 'Patients' AS grain, PATIENT_ID AS entity, SUM(BILLED_AMOUNT) AS amt
    FROM base GROUP BY PATIENT_ID
),
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
        ROW_NUMBER() OVER (PARTITION BY grain ORDER BY amt DESC)      AS rn,
        COUNT(*)    OVER (PARTITION BY grain)                         AS n_entities,
        SUM(amt)    OVER (PARTITION BY grain)                         AS grain_total,
        SUM(amt)    OVER (PARTITION BY grain ORDER BY amt DESC
                          ROWS BETWEEN UNBOUNDED PRECEDING
                                   AND CURRENT ROW)                   AS cum_amt
    FROM stacked
),
-- bucket every entity into its percentile slice, 1..100
bucketed AS (
    SELECT
        grain,
        CEIL(100.0 * rn / n_entities) AS pct_entities,
        cum_amt / grain_total         AS cum_share
    FROM ranked
)
-- the curve's value at percentile N is the running total at the LAST entity
-- inside that slice, so take the max within the bucket
SELECT
    grain                            AS "Grain",
    pct_entities                     AS "Pct Entities",
    ROUND(100 * MAX(cum_share), 2)   AS "Pct Spend"
FROM bucketed
GROUP BY grain, pct_entities
ORDER BY grain, pct_entities;

-- ---------------------------------------------------------------------
-- VERIFICATION, 2026-08-29. Output compared point-for-point against the
-- pre-existing q3_lorenz_points_2020_2024.csv, which had been produced by an
-- unsaved query. All 300 points match exactly -- same 300 keys, zero points
-- differing by more than 0.005pp. The old figures were right; they simply
-- could not be checked. The CSV is left byte-identical rather than rewritten,
-- so this file documents a reproduction rather than a change.
-- ---------------------------------------------------------------------
