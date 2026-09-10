-- =====================================================================
-- Q2: who actually pays? North star: patients bear X% of total spend,
-- insurers the rest, cut four ways (payer, payer type, encounter class,
-- year). The split relies on METHOD, not PAYER_ID -- ECHECK is the
-- insurer's channel, CASH/CHECK/CC/COPAY is the patient paying directly
-- (PAYER_ID only says who was billed). Long format (cut, segment) so the
-- dashboard can filter one result set.
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
    SELECT '1. Overall'        AS cut, 'All spend'          AS segment, * FROM base
    UNION ALL
    SELECT '2. Payer type',    PAYER_TYPE,                       * FROM base
    UNION ALL
    SELECT '3. Payer',         PAYER_NAME,                       * FROM base
    UNION ALL
    SELECT '4. Encounter class', ENCOUNTERCLASS,                 * FROM base
    UNION ALL
    SELECT '5. Year',          TO_VARCHAR(SERVICE_YEAR),         * FROM base
)
SELECT
    cut                                                        AS "Cut",
    segment                                                    AS "Segment",
    ROUND(SUM(BILLED_AMOUNT))                                  AS "Total Billed",
    ROUND(SUM(PAID_BY_PAYER))                                  AS "Paid by Insurer",
    ROUND(SUM(PAID_BY_PATIENT))                                AS "Paid by Patient",
    ROUND(100 * SUM(PAID_BY_PAYER)
          / NULLIF(SUM(PAID_BY_PAYER) + SUM(PAID_BY_PATIENT), 0), 1)
                                                               AS "% Insurer",
    ROUND(100 * SUM(PAID_BY_PATIENT)
          / NULLIF(SUM(PAID_BY_PAYER) + SUM(PAID_BY_PATIENT), 0), 1)
                                                               AS "% Patient",
    -- per-patient averages. NOTE: a patient appears in several segments
    -- (multiple encounter classes, multiple years), so these counts do NOT
    -- sum across rows within a cut -- only the totals row is a true headcount.
    COUNT(DISTINCT PATIENT_ID)                                 AS "Patients",
    ROUND(SUM(BILLED_AMOUNT)   / NULLIF(COUNT(DISTINCT PATIENT_ID), 0), 2)
                                                               AS "Billed per Patient",
    ROUND(SUM(PAID_BY_PAYER)   / NULLIF(COUNT(DISTINCT PATIENT_ID), 0), 2)
                                                               AS "Insurer Paid per Patient",
    ROUND(SUM(PAID_BY_PATIENT) / NULLIF(COUNT(DISTINCT PATIENT_ID), 0), 2)
                                                               AS "Patient Paid per Patient"
FROM cuts
GROUP BY cut, segment
ORDER BY cut, SUM(PAID_BY_PATIENT) / NULLIF(SUM(PAID_BY_PAYER) + SUM(PAID_BY_PATIENT), 0) DESC;
