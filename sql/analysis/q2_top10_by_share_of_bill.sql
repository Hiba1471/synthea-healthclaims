-- =====================================================================
-- Q2: the ten conditions where patients carry the LARGEST SHARE of the
--     bill -- as opposed to the largest dollar amount.
--
-- Companion to q2_top10_patient_paid.sql. That query ranks by money; this
-- one ranks by proportion. The two lists share no members, which is the
-- point: a condition can take a lot of money from patients because the
-- bill is enormous (pregnancy), or because patients cover most of a small
-- bill (an ear infection).
--
-- Floor of 5,000 people affected, so a condition with a handful of patients
-- cannot top the list on a share computed from almost nothing.
--
-- Results: sql/results/q2_top10_by_share_of_bill_2020_2024.csv
-- =====================================================================
WITH claim_money AS (
    SELECT CLAIM_ID, MIN(PATIENT_ID) AS patient_id,
           SUM(PAID_AMOUNT) AS paid, SUM(PAID_BY_PATIENT) AS patient_paid
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
    WHERE NOT IS_ADMIN_NOISE_CODE AND PROCEDURECODE IS NOT NULL
    GROUP BY CLAIM_ID
),
claim_condition AS (
    SELECT c.CLAIM_ID,
           CASE WHEN d1.IS_CONDITION THEN c.DIAGNOSIS1
                WHEN d2.IS_CONDITION THEN c.DIAGNOSIS2 END AS condition_code
    FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.CLAIMS c
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d1 ON c.DIAGNOSIS1 = d1.CODE
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d2 ON c.DIAGNOSIS2 = d2.CODE
),
by_condition AS (
    SELECT d.DESCRIPTION AS condition_name,
           SUM(m.patient_paid) AS patient_paid, SUM(m.paid) AS paid,
           COUNT(DISTINCT m.patient_id) AS patients
    FROM claim_money m
    JOIN claim_condition cc ON m.CLAIM_ID = cc.CLAIM_ID
    JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d ON cc.condition_code = d.CODE
    WHERE cc.condition_code IS NOT NULL
    GROUP BY d.DESCRIPTION
    HAVING SUM(m.paid) > 0 AND COUNT(DISTINCT m.patient_id) >= 5000
)
SELECT
    ROW_NUMBER() OVER (ORDER BY patient_paid / paid DESC) AS "Rank by % of the bill patients pay",
    condition_name                                        AS "Condition",
    ROUND(100 * patient_paid / paid, 1)                   AS "% of the bill patients pay",
    ROUND(patient_paid)                                   AS "Paid by patients over 5 years",
    RANK() OVER (ORDER BY patient_paid DESC)              AS "Rank by money",
    patients                                              AS "People affected",
    ROUND(patient_paid / patients)                        AS "Paid per person over 5 years"
FROM by_condition
QUALIFY "Rank by % of the bill patients pay" <= 10
ORDER BY 1;
