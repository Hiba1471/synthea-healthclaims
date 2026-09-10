-- =====================================================================
-- BROAD ANALYSIS 3 of 3: trends over time
--
-- Spend, volume, cost per claim/patient and care-setting mix, by quarter
-- and by year, 2020-2024.
--
-- CAVEAT: the data ends 2024-11-09. Q4 2024 is ~2/3 of a quarter and the
-- 2024 year is ~10.5/12 months, so raw 2024 totals will LOOK like a decline
-- that is purely the data boundary. Ratios (cost per claim, mix %) stay
-- comparable; absolute totals do not. The IS_PARTIAL flag marks the
-- affected rows so charts can dash or drop them.
--
-- Results: sql/results/trends_quarterly_2020_2024.csv
-- =====================================================================

WITH base AS (
    SELECT
        SERVICE_YEAR,
        QUARTER(FROMDATE)                          AS qtr,
        DATE_TRUNC('quarter', FROMDATE)::DATE      AS quarter_start,
        ENCOUNTERCLASS,
        PAYER_TYPE,
        CLAIM_ID,
        PATIENT_ID,
        BILLED_AMOUNT,
        PAID_BY_PATIENT
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
    WHERE NOT IS_ADMIN_NOISE_CODE
      AND PROCEDURECODE IS NOT NULL
),
quarterly AS (
    SELECT
        quarter_start,
        SERVICE_YEAR,
        qtr,
        SUM(BILLED_AMOUNT)             AS billed,
        SUM(PAID_BY_PATIENT)           AS patient_paid,
        COUNT(DISTINCT CLAIM_ID)       AS claims,
        COUNT(DISTINCT PATIENT_ID)     AS patients
    FROM base
    GROUP BY 1,2,3
)
SELECT
    quarter_start                                          AS "Quarter",
    SERVICE_YEAR                                           AS "Year",
    'Q' || qtr                                             AS "Q",
    -- the final quarter is truncated by the data boundary
    IFF(SERVICE_YEAR = 2024 AND qtr = 4, TRUE, FALSE)      AS "Is Partial",
    ROUND(billed)                                          AS "Total Billed",
    claims                                                 AS "Claims",
    patients                                               AS "Patients",
    ROUND(billed / NULLIF(claims, 0), 2)                   AS "Billed per Claim",
    ROUND(billed / NULLIF(patients, 0), 2)                 AS "Billed per Patient",
    ROUND(claims / NULLIF(patients, 0), 2)                 AS "Claims per Patient",
    ROUND(100 * patient_paid / NULLIF(billed, 0), 1)       AS "% Borne by Patient",
    -- indexed to Q1 2020 = 100 so trend is readable independent of scale
    ROUND(100 * billed
          / FIRST_VALUE(billed) OVER (ORDER BY quarter_start), 1)
                                                           AS "Billed Indexed (Q1 2020=100)",
    ROUND(100 * (billed / NULLIF(claims, 0))
          / FIRST_VALUE(billed / NULLIF(claims, 0)) OVER (ORDER BY quarter_start), 1)
                                                           AS "Cost per Claim Indexed"
FROM quarterly
ORDER BY quarter_start;
