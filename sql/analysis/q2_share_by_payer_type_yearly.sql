-- =====================================================================
-- Q2: for the conditions where patients carry the most, is the
-- commercial/government gap stable year to year, or is it drift? Unlike
-- q2_top10_share_by_payer_type.sql, which pools all five years, this
-- computes each year separately and takes the MEDIAN, so one odd year
-- cannot dominate the ratio; lowest and highest year are emitted
-- alongside so the spread is visible. "Everyone" is the blended figure
-- nobody actually experiences, kept for comparison. Population floor of
-- 5,000 people per condition, matching q2_top10_share_by_payer_type.sql.
-- The care-type version is q2_care_type_share_by_payer_type.sql.
-- =====================================================================

WITH claim_money AS (
    SELECT
        CLAIM_ID,
        MIN(PATIENT_ID)      AS patient_id,
        MIN(PAYER_TYPE)      AS payer_type,
        MIN(SERVICE_YEAR)    AS service_year,
        SUM(PAID_AMOUNT)     AS paid,
        SUM(PAID_BY_PATIENT) AS patient_paid
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
    WHERE NOT IS_ADMIN_NOISE_CODE AND PROCEDURECODE IS NOT NULL
    GROUP BY CLAIM_ID
),
claim_condition AS (
    -- same DIAGNOSIS2 fallback used everywhere else in Q2
    SELECT c.CLAIM_ID,
           CASE WHEN d1.IS_CONDITION THEN c.DIAGNOSIS1
                WHEN d2.IS_CONDITION THEN c.DIAGNOSIS2 END AS condition_code
    FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.CLAIMS c
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d1 ON c.DIAGNOSIS1 = d1.CODE
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d2 ON c.DIAGNOSIS2 = d2.CODE
),
joined AS (
    SELECT m.patient_id, m.payer_type, m.service_year, m.paid, m.patient_paid,
           d.DESCRIPTION AS condition_name
    FROM claim_money m
    JOIN claim_condition cc ON m.CLAIM_ID = cc.CLAIM_ID
    JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d ON cc.condition_code = d.CODE
    WHERE cc.condition_code IS NOT NULL
),
top10 AS (
    SELECT condition_name,
           COUNT(DISTINCT patient_id) AS people,
           SUM(patient_paid) / NULLIF(SUM(paid), 0) AS pooled_share
    FROM joined
    GROUP BY condition_name
    HAVING COUNT(DISTINCT patient_id) >= 5000
    QUALIFY ROW_NUMBER() OVER (ORDER BY SUM(patient_paid) / NULLIF(SUM(paid),0) DESC) <= 10
),
yearly AS (
    SELECT
        j.condition_name,
        COALESCE(j.payer_type, 'Everyone')                    AS payer_type,
        j.service_year,
        100 * SUM(j.patient_paid) / NULLIF(SUM(j.paid), 0)    AS share_pct
    FROM joined j
    JOIN top10 t ON j.condition_name = t.condition_name
    GROUP BY GROUPING SETS (
        (j.condition_name, j.payer_type, j.service_year),
        (j.condition_name, j.service_year)
    )
    HAVING SUM(j.paid) > 0
)
SELECT
    y.condition_name                        AS "Condition",
    y.payer_type                            AS "Kind of insurance",
    ROUND(MEDIAN(y.share_pct), 1)           AS "Typical % of the bill the patient pays",
    ROUND(MIN(y.share_pct), 1)              AS "Lowest year",
    ROUND(MAX(y.share_pct), 1)              AS "Highest year",
    COUNT(*)                                AS "Years counted",
    ROUND(100 * t.pooled_share, 1)          AS "All 5 years pooled - everyone",
    t.people                                AS "People affected"
FROM yearly y
JOIN top10 t ON y.condition_name = t.condition_name
GROUP BY y.condition_name, y.payer_type, t.pooled_share, t.people
ORDER BY t.pooled_share DESC, y.payer_type;
