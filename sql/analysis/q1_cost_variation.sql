-- =====================================================================
-- Q1 EXTENSION: does cost per claim for the same condition vary by
-- payer type or by hospital?
--
-- Cost per claim is the right metric here: it holds the billing unit
-- constant, so the same condition can be compared across providers and
-- payers without volume or severity-mix distorting it.
--
-- Two result sets, distinguished by the "Dimension" column:
--   'Payer type'  -- 20 conditions x 3 payer types
--   'Hospital'    -- spread of cost per claim ACROSS hospitals, per
--                    condition (min / median / max / ratio), not one row
--                    per hospital
--
-- Volume floor of 30 claims per hospital-condition pair: without it a
-- hospital with 2 claims sets the min or max and the spread is noise.
-- (Same lesson as ranking hospitals by cost per patient, where a 4-patient
-- site topped the list until a floor was added.)
--
-- Results: sql/results/q1_cost_variation_2020_2024.csv
-- =====================================================================

WITH claim_money AS (
    SELECT
        v.CLAIM_ID,
        MIN(v.ENCOUNTER_ID)  AS encounter_id,
        MIN(v.PAYER_TYPE)    AS payer_type,
        SUM(v.BILLED_AMOUNT) AS billed
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN v
    WHERE NOT v.IS_ADMIN_NOISE_CODE
      AND v.PROCEDURECODE IS NOT NULL
    GROUP BY v.CLAIM_ID
    HAVING SUM(v.BILLED_AMOUNT) > 0
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
-- the established top 20 by total spend
top20 AS (
    SELECT cc.condition_code, SUM(m.billed) AS total_billed,
           ROW_NUMBER() OVER (ORDER BY SUM(m.billed) DESC) AS rank
    FROM claim_money m
    JOIN claim_condition cc ON m.CLAIM_ID = cc.CLAIM_ID
    WHERE cc.condition_code IS NOT NULL
    GROUP BY cc.condition_code
    QUALIFY rank <= 20
),
scoped AS (
    SELECT
        t.rank,
        d.DESCRIPTION AS condition_name,
        m.payer_type,
        e.ORGANIZATION_ID,
        m.billed
    FROM claim_money m
    JOIN claim_condition cc ON m.CLAIM_ID = cc.CLAIM_ID
    JOIN top20 t ON cc.condition_code = t.condition_code
    JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d ON t.condition_code = d.CODE
    JOIN SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.ENCOUNTERS e
      ON m.encounter_id = e.ENCOUNTER_ID
),

-- ---- cut 1: by payer type ---------------------------------------------
by_payer AS (
    SELECT
        'Payer type'            AS dimension,
        rank, condition_name,
        payer_type              AS segment,
        COUNT(*)                AS claims,
        ROUND(SUM(billed) / COUNT(*), 2) AS cost_per_claim
    FROM scoped
    GROUP BY rank, condition_name, payer_type
),

-- ---- cut 2: spread across hospitals ------------------------------------
per_hospital AS (
    SELECT rank, condition_name, ORGANIZATION_ID,
           COUNT(*) AS claims,
           SUM(billed) / COUNT(*) AS cost_per_claim
    FROM scoped
    GROUP BY rank, condition_name, ORGANIZATION_ID
    HAVING COUNT(*) >= 30              -- volume floor
),
by_hospital AS (
    SELECT
        'Hospital'                                   AS dimension,
        rank, condition_name,
        'across ' || COUNT(*) || ' hospitals'        AS segment,
        SUM(claims)                                  AS claims,
        ROUND(MEDIAN(cost_per_claim), 2)             AS cost_per_claim
    FROM per_hospital
    GROUP BY rank, condition_name
)

SELECT
    dimension                AS "Dimension",
    rank                     AS "Rank",
    condition_name           AS "Condition",
    segment                  AS "Segment",
    claims                   AS "Claims",
    cost_per_claim           AS "Cost per Claim"
FROM by_payer
UNION ALL
SELECT dimension, rank, condition_name, segment, claims, cost_per_claim
FROM by_hospital
ORDER BY "Dimension", "Rank", "Segment";
