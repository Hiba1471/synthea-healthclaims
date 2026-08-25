-- =====================================================================
-- Concussion in detail: why do patients pay two-thirds of the bill?
--
-- Concussion tops the "share of the bill patients pay" ranking at 67.9%,
-- yet contributes almost nothing in dollars. This pulls apart why: the
-- money, the visits, who insures these patients, and what is billed.
--
-- Three separate concussion codes exist in the data, so all are reported
-- together and individually.
--
-- Results: sql/results/q2_concussion_detail_2020_2024.csv
-- =====================================================================
WITH concussion_codes AS (
    SELECT CODE, DESCRIPTION
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY
    WHERE LOWER(DESCRIPTION) LIKE '%concussion%' AND IS_CONDITION
),
claim_money AS (
    SELECT CLAIM_ID, MIN(PATIENT_ID) AS patient_id, MIN(PAYER_TYPE) AS payer_type,
           MIN(ENCOUNTERCLASS) AS setting,
           SUM(BILLED_AMOUNT) AS billed, SUM(PAID_AMOUNT) AS paid,
           SUM(PAID_BY_PATIENT) AS patient_paid
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
scoped AS (
    SELECT k.DESCRIPTION AS condition_name, m.*
    FROM claim_money m
    JOIN claim_condition cc ON m.CLAIM_ID = cc.CLAIM_ID
    JOIN concussion_codes k ON cc.condition_code = k.CODE
)
SELECT 'By concussion type' AS "Breakdown", condition_name AS "Group",
       COUNT(*) AS "Claims", COUNT(DISTINCT patient_id) AS "People affected",
       ROUND(SUM(billed)) AS "Total bill", ROUND(SUM(patient_paid)) AS "Paid by patients",
       ROUND(100*SUM(patient_paid)/NULLIF(SUM(paid),0),1) AS "% of the bill patients pay",
       ROUND(SUM(billed)/COUNT(*)) AS "Cost per claim",
       ROUND(SUM(patient_paid)/NULLIF(COUNT(DISTINCT patient_id),0)) AS "Paid per person"
FROM scoped GROUP BY condition_name
UNION ALL
SELECT 'By kind of insurance', payer_type, COUNT(*), COUNT(DISTINCT patient_id),
       ROUND(SUM(billed)), ROUND(SUM(patient_paid)),
       ROUND(100*SUM(patient_paid)/NULLIF(SUM(paid),0),1),
       ROUND(SUM(billed)/COUNT(*)), ROUND(SUM(patient_paid)/NULLIF(COUNT(DISTINCT patient_id),0))
FROM scoped GROUP BY payer_type
UNION ALL
SELECT 'By type of visit', setting, COUNT(*), COUNT(DISTINCT patient_id),
       ROUND(SUM(billed)), ROUND(SUM(patient_paid)),
       ROUND(100*SUM(patient_paid)/NULLIF(SUM(paid),0),1),
       ROUND(SUM(billed)/COUNT(*)), ROUND(SUM(patient_paid)/NULLIF(COUNT(DISTINCT patient_id),0))
FROM scoped GROUP BY setting
UNION ALL
SELECT 'ALL CONCUSSIONS', 'combined', COUNT(*), COUNT(DISTINCT patient_id),
       ROUND(SUM(billed)), ROUND(SUM(patient_paid)),
       ROUND(100*SUM(patient_paid)/NULLIF(SUM(paid),0),1),
       ROUND(SUM(billed)/COUNT(*)), ROUND(SUM(patient_paid)/NULLIF(COUNT(DISTINCT patient_id),0))
FROM scoped
ORDER BY "Breakdown", "Paid by patients" DESC;
