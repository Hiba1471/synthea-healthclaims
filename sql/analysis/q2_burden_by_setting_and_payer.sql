-- =====================================================================
-- Q2: how does the patient's share differ by BOTH type of visit AND kind
--     of insurance?
--
-- q2_who_pays.sql cuts one dimension at a time. This crosses them, which is
-- where the interaction shows: a commercially-insured patient pays 82.7% of
-- a wellness visit, while a government-covered patient pays 7.6% for the
-- same kind of visit.
--
-- "Patient pays" is identified by METHOD on PAYMENT rows -- ECHECK is the
-- insurer's electronic channel, cash / cheque / card / copay are the patient
-- paying directly. The insurer named on the encounter only tells you who was
-- BILLED, not who paid.
--
-- Results: sql/results/q2_burden_by_setting_and_payer_2020_2024.csv
-- =====================================================================

SELECT
    ENCOUNTERCLASS                                    AS "Type of visit",
    PAYER_TYPE                                        AS "Kind of insurance",
    ROUND(SUM(BILLED_AMOUNT))                         AS "Total bill",
    ROUND(SUM(PAID_BY_PAYER))                         AS "Paid by the insurer",
    ROUND(SUM(PAID_BY_PATIENT))                       AS "Paid by the patient",
    ROUND(100 * SUM(PAID_BY_PATIENT)
          / NULLIF(SUM(PAID_BY_PAYER) + SUM(PAID_BY_PATIENT), 0), 1)
                                                      AS "% of the bill the patient pays",
    COUNT(DISTINCT PATIENT_ID)                        AS "People affected",
    ROUND(SUM(PAID_BY_PATIENT)
          / NULLIF(COUNT(DISTINCT PATIENT_ID), 0))    AS "Paid per person over 5 years",
    -- how this visit type compares to the same insurance type overall
    ROUND(100 * SUM(PAID_BY_PATIENT)
          / NULLIF(SUM(PAID_BY_PAYER) + SUM(PAID_BY_PATIENT), 0)
          - 100 * SUM(SUM(PAID_BY_PATIENT)) OVER (PARTITION BY PAYER_TYPE)
          / NULLIF(SUM(SUM(PAID_BY_PAYER) + SUM(PAID_BY_PATIENT))
                   OVER (PARTITION BY PAYER_TYPE), 0), 1)
                                                      AS "Points above or below that insurance type's average"
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
WHERE NOT IS_ADMIN_NOISE_CODE
  AND PROCEDURECODE IS NOT NULL
GROUP BY ENCOUNTERCLASS, PAYER_TYPE
HAVING SUM(BILLED_AMOUNT) > 0
ORDER BY PAYER_TYPE, SUM(PAID_BY_PATIENT) DESC;
