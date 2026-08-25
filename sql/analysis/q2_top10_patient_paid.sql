-- =====================================================================
-- Q2: the ten conditions patients paid the most for themselves, 2020-2024
--
-- "Paid by patients" means money that came from the patient rather than
-- their insurer. It is identified by METHOD on PAYMENT rows -- ECHECK is the
-- insurer's electronic channel, while cash, cheque, card and copay are the
-- patient paying directly. The insurer named on an encounter only records
-- who was BILLED, not who actually paid.
--
-- Condition attribution follows Q1: use DIAGNOSIS1 when it is a real
-- condition, otherwise fall back to DIAGNOSIS2, because DIAGNOSIS1 in this
-- data is roughly two-thirds encounter metadata rather than an illness.
--
-- CAVEAT: pregnancy and allergy dollar figures are inflated by Synthea's
-- procedure pricing (see DATA_ANALYSIS_CONTEXT.md section 27). The
-- percentage and people-affected columns are unaffected.
--
-- Results: sql/results/q2_top10_patient_paid_2020_2024.csv
-- =====================================================================

WITH claim_money AS (
    SELECT
        CLAIM_ID,
        MIN(PATIENT_ID)      AS patient_id,
        SUM(BILLED_AMOUNT)   AS billed,
        SUM(PAID_AMOUNT)     AS paid,
        SUM(PAID_BY_PATIENT) AS patient_paid
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
    WHERE NOT IS_ADMIN_NOISE_CODE
      AND PROCEDURECODE IS NOT NULL
    GROUP BY CLAIM_ID
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
by_condition AS (
    SELECT
        d.DESCRIPTION                AS condition_name,
        SUM(m.patient_paid)          AS patient_paid,
        SUM(m.paid)                  AS paid,
        SUM(m.billed)                AS billed,
        COUNT(DISTINCT m.patient_id) AS patients
    FROM claim_money m
    JOIN claim_condition cc ON m.CLAIM_ID = cc.CLAIM_ID
    JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d ON cc.condition_code = d.CODE
    WHERE cc.condition_code IS NOT NULL
    GROUP BY d.DESCRIPTION
    HAVING SUM(m.patient_paid) > 0
)
SELECT
    ROW_NUMBER() OVER (ORDER BY patient_paid DESC)      AS "Rank",
    condition_name                                      AS "Condition",
    ROUND(patient_paid)                                 AS "Paid by patients over 5 years",
    ROUND(100 * patient_paid / SUM(patient_paid) OVER (), 1)
                                                        AS "% of everything patients paid",
    ROUND(100 * SUM(patient_paid) OVER (ORDER BY patient_paid DESC
                                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
          / SUM(patient_paid) OVER (), 1)               AS "Running % of everything patients paid",
    ROUND(100 * patient_paid / NULLIF(paid, 0), 1)      AS "% of the bill patients pay",
    -- separate ranking: where this sits among ALL 183 conditions on the
    -- share patients carry, not on dollars. The two orders differ sharply.
    RANK() OVER (ORDER BY patient_paid / NULLIF(paid, 0) DESC)
                                                        AS "Rank by % of the bill patients pay",
    patients                                            AS "People affected",
    ROUND(patient_paid / NULLIF(patients, 0))           AS "Paid per person over 5 years",
    ROUND(billed)                                       AS "Total bill including insurer"
FROM by_condition
QUALIFY "Rank" <= 10
ORDER BY "Rank";
