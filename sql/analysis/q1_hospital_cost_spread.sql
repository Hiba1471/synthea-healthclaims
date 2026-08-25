-- =====================================================================
-- Q1: how much does the price of the same condition differ between
--     hospitals?
--
-- Two-stage aggregation, and the order matters:
--   stage 1  work out cost per claim for EACH hospital x condition
--   stage 2  measure the spread ACROSS those hospital values
-- Pooling all claims and taking percentiles directly would measure how much
-- individual claims vary inside hospitals -- a different question.
--
-- Two spread measures are reported because they disagree, and the
-- disagreement is the finding:
--   dearest / cheapest   the full range. One unusual hospital sets it.
--   variation score      the gap between the cheapest and dearest QUARTER of
--                        hospitals, as a share of the typical price. Ignores
--                        both tails.
-- End-stage renal disease reads 163x on the first and 0.17 on the second:
-- ordinary hospitals bill almost identically and one or two outliers create
-- the range. Ranking by the full range highlights exactly the conditions
-- whose variation is illusory.
--
-- Floor of 30 claims per hospital-condition pair: without it a hospital with
-- two claims sets the cheapest or dearest value and the spread is noise.
--
-- Results: sql/results/q1_hospital_cost_spread_2020_2024.csv
-- =====================================================================

WITH claim_money AS (
    SELECT
        CLAIM_ID,
        MIN(ENCOUNTER_ID)  AS encounter_id,
        SUM(BILLED_AMOUNT) AS billed
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
    WHERE NOT IS_ADMIN_NOISE_CODE
      AND PROCEDURECODE IS NOT NULL
    GROUP BY CLAIM_ID
    HAVING SUM(BILLED_AMOUNT) > 0
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
-- the 20 biggest-spend conditions, and their spend rank
top_conditions AS (
    SELECT
        cc.condition_code,
        ROW_NUMBER() OVER (ORDER BY SUM(m.billed) DESC) AS spend_rank
    FROM claim_money m
    JOIN claim_condition cc ON m.CLAIM_ID = cc.CLAIM_ID
    WHERE cc.condition_code IS NOT NULL
    GROUP BY cc.condition_code
    QUALIFY spend_rank <= 20
),
-- stage 1: one cost-per-claim figure per hospital, per condition
per_hospital AS (
    SELECT
        t.spend_rank,
        d.DESCRIPTION            AS condition_name,
        e.ORGANIZATION_ID,
        COUNT(*)                 AS claims,
        SUM(m.billed) / COUNT(*) AS cost_per_claim
    FROM claim_money m
    JOIN claim_condition cc ON m.CLAIM_ID = cc.CLAIM_ID
    JOIN top_conditions t   ON cc.condition_code = t.condition_code
    JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d ON t.condition_code = d.CODE
    JOIN SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.ENCOUNTERS e
      ON m.encounter_id = e.ENCOUNTER_ID
    GROUP BY t.spend_rank, d.DESCRIPTION, e.ORGANIZATION_ID
    HAVING COUNT(*) >= 30
)
-- stage 2: spread across hospitals
SELECT
    spend_rank                                        AS "Rank by total spend",
    condition_name                                    AS "Condition",
    COUNT(*)                                          AS "Hospitals compared",
    SUM(claims)                                       AS "Claims covered",
    ROUND(MIN(cost_per_claim))                        AS "Cheapest hospital",
    ROUND(APPROX_PERCENTILE(cost_per_claim, 0.25))    AS "Cheaper quarter starts at",
    ROUND(MEDIAN(cost_per_claim))                     AS "Typical hospital",
    ROUND(APPROX_PERCENTILE(cost_per_claim, 0.75))    AS "Dearer quarter starts at",
    ROUND(MAX(cost_per_claim))                        AS "Dearest hospital",
    ROUND(MAX(cost_per_claim) / NULLIF(MIN(cost_per_claim), 0), 1)
                                                      AS "Dearest vs cheapest",
    -- the measure to rank on: spread of the middle half, relative to typical
    ROUND((APPROX_PERCENTILE(cost_per_claim, 0.75)
           - APPROX_PERCENTILE(cost_per_claim, 0.25))
          / NULLIF(MEDIAN(cost_per_claim), 0), 3)     AS "Variation score"
FROM per_hospital
GROUP BY spend_rank, condition_name
ORDER BY spend_rank;
