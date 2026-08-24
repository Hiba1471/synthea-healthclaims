-- =====================================================================
-- Q2 EXTENSION: which conditions cost patients the most out of pocket?
--
-- "Out of pocket" = the share a patient pays themselves rather than their
-- insurer, identified by METHOD on PAYMENT rows (ECHECK = insurer channel;
-- CASH / CHECK / CC / COPAY = the patient paying directly).
--
-- Ranked by TOTAL patient out-of-pocket dollars. Two other orderings are in
-- the output and rank very differently:
--   "% of Bill Patient Pays"      -- the rate. Acute viral pharyngitis tops
--                                    this at 43.5% but is only 16th in dollars.
--   "Out of Pocket per Patient"   -- what one person pays. Lung cancer has the
--                                    lowest rate (5.4%) but the highest per
--                                    patient ($75,965).
--
-- Same condition attribution as Q1: DIAGNOSIS1 when it is a real condition,
-- else DIAGNOSIS2.
--
-- CAVEAT: pregnancy and allergy dollar figures are inflated by Synthea's
-- procedure pricing (see section 27, Q1). The percentage columns are not.
--
-- Results: sql/results/q2_oop_by_condition_2020_2024.csv
-- =====================================================================

WITH claim_money AS (
    SELECT CLAIM_ID, MIN(PATIENT_ID) AS patient_id,
           SUM(BILLED_AMOUNT) AS billed, SUM(PAID_AMOUNT) AS paid,
           SUM(PAID_BY_PATIENT) AS patient_paid
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
    WHERE NOT IS_ADMIN_NOISE_CODE AND PROCEDURECODE IS NOT NULL
    GROUP BY CLAIM_ID
),
cc AS (
    SELECT c.CLAIM_ID,
           CASE WHEN d1.IS_CONDITION THEN c.DIAGNOSIS1
                WHEN d2.IS_CONDITION THEN c.DIAGNOSIS2 END AS code
    FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.CLAIMS c
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d1 ON c.DIAGNOSIS1=d1.CODE
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d2 ON c.DIAGNOSIS2=d2.CODE
)
SELECT
    d.DESCRIPTION                                            AS "Condition",
    ROUND(SUM(m.patient_paid))                               AS "Patient Out of Pocket",
    ROUND(100*SUM(m.patient_paid)/SUM(SUM(m.patient_paid)) OVER (), 2)
                                                             AS "% of All Patient Out of Pocket",
    ROUND(100*SUM(m.patient_paid)/NULLIF(SUM(m.paid),0), 1)   AS "% of Bill Patient Pays",
    COUNT(DISTINCT m.patient_id)                             AS "Patients",
    ROUND(SUM(m.patient_paid)/NULLIF(COUNT(DISTINCT m.patient_id),0)) AS "Out of Pocket per Patient",
    ROUND(SUM(m.billed))                                     AS "Total Billed"
FROM claim_money m
JOIN cc ON m.CLAIM_ID = cc.CLAIM_ID
JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d ON cc.code = d.CODE
WHERE cc.code IS NOT NULL
GROUP BY d.DESCRIPTION
HAVING SUM(m.patient_paid) > 0
ORDER BY SUM(m.patient_paid) DESC;
