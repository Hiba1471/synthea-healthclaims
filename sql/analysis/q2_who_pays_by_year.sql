-- =====================================================================
-- Q2 EXTENSION: who pays, broken out BY YEAR
--
-- Same splits as q2_who_pays.sql but with SERVICE_YEAR as a second
-- dimension, so trends are visible: is patient burden rising, and is it
-- rising evenly across payers and settings?
--
-- CAVEAT: 2024 data stops 2024-11-09, so 2024 per-patient BILLED figures
-- run ~15% light. Percentages and ratios remain comparable; absolute
-- annual totals for 2024 do not.
--
-- Results: sql/results/q2_who_pays_by_year_2020_2024.csv
-- =====================================================================

WITH base AS (
    SELECT
        PAYER_NAME, PAYER_TYPE, ENCOUNTERCLASS, SERVICE_YEAR, PATIENT_ID,
        BILLED_AMOUNT, PAID_BY_PAYER, PAID_BY_PATIENT
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
    WHERE NOT IS_ADMIN_NOISE_CODE
      AND PROCEDURECODE IS NOT NULL
),
cuts AS (
    SELECT '1. Overall'         AS cut, 'All spend' AS segment, * FROM base
    UNION ALL
    SELECT '2. Payer type',     PAYER_TYPE,     * FROM base
    UNION ALL
    SELECT '3. Payer',          PAYER_NAME,     * FROM base
    UNION ALL
    SELECT '4. Encounter class', ENCOUNTERCLASS, * FROM base
)
SELECT
    cut                                                        AS "Cut",
    segment                                                    AS "Segment",
    SERVICE_YEAR                                               AS "Year",
    COUNT(DISTINCT PATIENT_ID)                                 AS "Patients",
    ROUND(SUM(BILLED_AMOUNT))                                  AS "Total Billed",
    ROUND(SUM(PAID_BY_PATIENT))                                AS "Paid by Patient",
    ROUND(100 * SUM(PAID_BY_PATIENT)
          / NULLIF(SUM(PAID_BY_PAYER) + SUM(PAID_BY_PATIENT), 0), 1)
                                                               AS "% Patient",
    ROUND(SUM(BILLED_AMOUNT)   / NULLIF(COUNT(DISTINCT PATIENT_ID), 0), 2)
                                                               AS "Billed per Patient",
    ROUND(SUM(PAID_BY_PATIENT) / NULLIF(COUNT(DISTINCT PATIENT_ID), 0), 2)
                                                               AS "Patient Paid per Patient"
FROM cuts
GROUP BY cut, segment, SERVICE_YEAR
ORDER BY cut, segment, SERVICE_YEAR;
