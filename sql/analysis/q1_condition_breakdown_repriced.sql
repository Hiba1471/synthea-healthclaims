-- =====================================================================
-- REFERENCE TABLE, NOT A CORRECTED DATASET: all 185 conditions, with the
-- eleven confidently-inflated conditions divided down to their real-world
-- benchmark and the other 174 (including the four checked and found NOT
-- inflated, and the five with no defensible correction factor) left exactly
-- as billed.
--
-- NOTHING IN THE REPORT IS DRAWN FROM THIS. It was written when the plan was
-- to replace the client report's primary Q1 charts with price-corrected
-- versions; that plan was cancelled, and the primary charts still show real,
-- as-billed data. The file is kept because the underlying question -- what
-- does the condition ranking look like once known pricing defects are
-- corrected -- is worth having answered and traceable, not because anything
-- depends on it. If a chart is ever built from this, say plainly on the
-- chart that it is corrected rather than observed.
--
-- Same eleven divisors as q1_multi_condition_sensitivity.sql, applied here
-- to BILLED_AMOUNT only (this file covers total billed and cost per person,
-- not payer split -- q2_care_type_breakdown_repriced.sql is the one that
-- also touches PAID_BY_PATIENT/PAID_BY_PAYER).
--
-- Headline: chronic kidney disease becomes the largest condition at 19.2% of
-- a $22.9B corrected diagnosed total, having never been corrected itself --
-- everything around it shrank. Pregnancy falls to 2nd at 14.7%, and its
-- corrected cost per person lands at $18,864 against the $18,865 KFF
-- benchmark used to derive the divisor, which is the arithmetic closing on
-- itself rather than an independent confirmation.
--
-- The as-billed sources (q1_spend_decomposition_2020_2024.csv,
-- dashboard/q1_donut.html, dashboard/where_the_money_goes.html) are
-- UNTOUCHED and remain the real documentation of the database.
--
-- Results: sql/results/q1_condition_breakdown_repriced_2020_2024.csv
-- =====================================================================

WITH claim_money AS (
    SELECT CLAIM_ID, MIN(PATIENT_ID) AS patient_id, SUM(BILLED_AMOUNT) AS billed
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
    WHERE NOT IS_ADMIN_NOISE_CODE AND PROCEDURECODE IS NOT NULL
    GROUP BY CLAIM_ID
),
claim_condition AS (
    SELECT c.CLAIM_ID,
           CASE WHEN d1.IS_CONDITION THEN c.DIAGNOSIS1 WHEN d2.IS_CONDITION THEN c.DIAGNOSIS2 END AS condition_code
    FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.CLAIMS c
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d1 ON c.DIAGNOSIS1 = d1.CODE
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d2 ON c.DIAGNOSIS2 = d2.CODE
),
repriced AS (
    SELECT
        cc.condition_code,
        m.patient_id,
        m.billed / CASE cc.condition_code
            WHEN '72892002'  THEN 8.587
            WHEN '419199007' THEN 88.976
            WHEN '66383009'  THEN 12.542
            WHEN '18718003'  THEN 7.522
            WHEN '424132000' THEN 11.038
            WHEN '68496003'  THEN 19.736
            WHEN '312608009' THEN 5.285
            WHEN '109570002' THEN 16.564
            WHEN '10509002'  THEN 9.252
            WHEN '230690007' THEN 3.836
            WHEN '307426000' THEN 23.590
            ELSE 1
        END AS billed
    FROM claim_money m
    JOIN claim_condition cc ON m.CLAIM_ID = cc.CLAIM_ID
    WHERE cc.condition_code IS NOT NULL
)
SELECT
    d.DESCRIPTION                          AS "Condition",
    ROUND(SUM(r.billed))                   AS "Total billed",
    COUNT(DISTINCT r.patient_id)           AS "People affected",
    ROUND(SUM(r.billed) / COUNT(DISTINCT r.patient_id)) AS "Cost per person"
FROM repriced r
JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d ON r.condition_code = d.CODE
GROUP BY d.DESCRIPTION
HAVING SUM(r.billed) > 0
ORDER BY "Total billed" DESC;
