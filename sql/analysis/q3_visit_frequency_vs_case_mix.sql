-- =====================================================================
-- Q3 follow-up: q3_price_vs_casemix.sql showed cost per visit is not
-- price. If price is flat, is the spread UTILISATION (same patients,
-- more done -- actionable) or COMPOSITION (different patients or care
-- pathway -- not actionable)? Two tests: procedures-per-claim spread
-- across sites for the same condition (almost none, except pregnancy),
-- then what the cheapest vs. dearest pregnancy sites actually bill for.
--
-- Result: composition. Cheap sites deliver babies; expensive sites run
-- antenatal clinics that accumulate charges over nine months -- not the
-- same work at different intensity, but different halves of the pathway.
--
-- TRAP: sizing "excess over the median site" naively gives $17.3B on
-- pregnancy alone. DO NOT report that figure -- it assumes every site
-- could reach the median, which this query shows they cannot.
-- =====================================================================

WITH claim_condition AS (
    SELECT c.CLAIM_ID,
           CASE WHEN d1.IS_CONDITION THEN c.DIAGNOSIS1
                WHEN d2.IS_CONDITION THEN c.DIAGNOSIS2 END AS condition_code
    FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.CLAIMS c
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d1 ON c.DIAGNOSIS1 = d1.CODE
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d2 ON c.DIAGNOSIS2 = d2.CODE
),
line AS (
    SELECT v.CLAIM_ID, v.ENCOUNTER_ID, v.PROCEDURECODE, v.BILLED_AMOUNT
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN v
    WHERE NOT v.IS_ADMIN_NOISE_CODE
      AND v.PROCEDURECODE IS NOT NULL
      AND v.BILLED_AMOUNT > 0
),
per_claim AS (
    SELECT o.NAME || ' (' || o.CITY || ')' AS hospital,
           cc.condition_code,
           l.CLAIM_ID,
           COUNT(DISTINCT l.PROCEDURECODE) AS procs,
           SUM(l.BILLED_AMOUNT)            AS billed
    FROM line l
    JOIN claim_condition cc ON l.CLAIM_ID = cc.CLAIM_ID
    JOIN SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.ENCOUNTERS e
      ON l.ENCOUNTER_ID = e.ENCOUNTER_ID
    JOIN SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.ORGANIZATIONS o
      ON e.ORGANIZATION_ID = o.ORGANIZATION_ID
    WHERE cc.condition_code IS NOT NULL
    GROUP BY 1, 2, 3
),
-- same floor as q1_hospital_variability: a site needs real volume in a
-- condition before its average means anything
site_cond AS (
    SELECT hospital, condition_code,
           COUNT(*)    AS claims,
           AVG(procs)  AS procs_per_claim,
           AVG(billed) AS billed_per_claim
    FROM per_claim
    GROUP BY 1, 2
    HAVING COUNT(*) >= 30
)
SELECT
    d.DESCRIPTION                                                AS "Condition",
    COUNT(*)                                                     AS "Hospitals",
    ROUND(MEDIAN(procs_per_claim), 2)                            AS "Procedures per claim, typical site",
    ROUND(APPROX_PERCENTILE(procs_per_claim, 0.25), 2)           AS "P25 procedures per claim",
    ROUND(APPROX_PERCENTILE(procs_per_claim, 0.75), 2)           AS "P75 procedures per claim",
    -- how much the AMOUNT OF WORK varies between sites. Low = hospitals do the
    -- same things; high is the only case worth investigating further.
    ROUND((APPROX_PERCENTILE(procs_per_claim, 0.75)
           - APPROX_PERCENTILE(procs_per_claim, 0.25))
          / NULLIF(MEDIAN(procs_per_claim), 0), 3)               AS "Variation in amount of work",
    ROUND((APPROX_PERCENTILE(billed_per_claim, 0.75)
           - APPROX_PERCENTILE(billed_per_claim, 0.25))
          / NULLIF(MEDIAN(billed_per_claim), 0), 3)              AS "Variation in cost"
FROM site_cond s
JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d ON s.condition_code = d.CODE
GROUP BY d.DESCRIPTION
HAVING COUNT(*) >= 20
ORDER BY "Variation in amount of work" DESC;
