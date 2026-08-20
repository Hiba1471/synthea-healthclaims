-- =====================================================================
-- BROAD ANALYSIS 1 of 3: cost distribution percentiles
--
-- Question: what does a "typical" claim/encounter/patient actually cost?
-- Averages are misleading on healthcare spend because the distribution is
-- heavily right-skewed -- a small number of very expensive cases drag the
-- mean far above the median. The mean-vs-median gap IS the finding.
--
-- Three grains, because "cost" means different things:
--   CLAIM     one billing event
--   ENCOUNTER one visit (may span several claims)
--   PATIENT   lifetime-in-window spend per person
--
-- Reads V_CLAIMS_TX_CLEAN, so the 2020-2024 window and the corrected
-- BILLED_AMOUNT (CHARGE rows only, no double-counted transfers) are inherited.
-- Results: sql/results/cost_percentiles_2020_2024.csv
-- =====================================================================

WITH claim_totals AS (
    SELECT CLAIM_ID, SUM(BILLED_AMOUNT) AS amt
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
    GROUP BY CLAIM_ID
    HAVING SUM(BILLED_AMOUNT) > 0
),
encounter_totals AS (
    SELECT ENCOUNTER_ID, SUM(BILLED_AMOUNT) AS amt
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
    GROUP BY ENCOUNTER_ID
    HAVING SUM(BILLED_AMOUNT) > 0
),
patient_totals AS (
    SELECT PATIENT_ID, SUM(BILLED_AMOUNT) AS amt
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
    GROUP BY PATIENT_ID
    HAVING SUM(BILLED_AMOUNT) > 0
),
stacked AS (
    SELECT 'per claim'     AS grain, amt FROM claim_totals
    UNION ALL
    SELECT 'per encounter', amt FROM encounter_totals
    UNION ALL
    SELECT 'per patient',   amt FROM patient_totals
)
SELECT
    grain,
    COUNT(*)                                        AS n,
    ROUND(SUM(amt))                                 AS total_billed,
    ROUND(MIN(amt), 2)                              AS min,
    ROUND(APPROX_PERCENTILE(amt, 0.01), 2)          AS p01,
    ROUND(APPROX_PERCENTILE(amt, 0.05), 2)          AS p05,
    ROUND(APPROX_PERCENTILE(amt, 0.25), 2)          AS p25,
    ROUND(APPROX_PERCENTILE(amt, 0.50), 2)          AS p50_median,
    ROUND(AVG(amt), 2)                              AS mean,
    ROUND(APPROX_PERCENTILE(amt, 0.75), 2)          AS p75,
    ROUND(APPROX_PERCENTILE(amt, 0.90), 2)          AS p90,
    ROUND(APPROX_PERCENTILE(amt, 0.95), 2)          AS p95,
    ROUND(APPROX_PERCENTILE(amt, 0.99), 2)          AS p99,
    ROUND(MAX(amt), 2)                              AS max,
    -- skew indicators
    ROUND(AVG(amt) / NULLIF(APPROX_PERCENTILE(amt, 0.50), 0), 2)
                                                    AS mean_over_median,
    ROUND(APPROX_PERCENTILE(amt, 0.99)
          / NULLIF(APPROX_PERCENTILE(amt, 0.50), 0), 1)
                                                    AS p99_over_median
FROM stacked
GROUP BY grain
ORDER BY CASE grain WHEN 'per claim' THEN 1 WHEN 'per encounter' THEN 2 ELSE 3 END;
