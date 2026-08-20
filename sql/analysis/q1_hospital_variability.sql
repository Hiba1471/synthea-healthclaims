-- =====================================================================
-- Q1 EXTENSION: how variable is each condition's cost per claim ACROSS
-- hospitals, and how do conditions classify by that variability?
--
-- METHOD -- two-stage aggregation:
--   stage 1: cost per claim for EACH hospital x condition
--   stage 2: dispersion statistics ACROSS those hospital values
-- Percentiles/SD are taken across HOSPITALS, not across claims. Pooling
-- claims would measure within-hospital case mix instead.
--
-- TWO DISPERSION MEASURES, deliberately:
--   CV  = STDDEV / MEAN            scale-free, but mean-based so a single
--                                  outlier hospital inflates it
--   RCV = (P75 - P25) / MEDIAN     quartile dispersion, ignores both tails
--
-- Reporting both is the point: where they disagree, variation is driven by
-- a few outlier sites rather than by genuine spread. ESRD reads 162x on
-- max/min but ~1.2x across the middle half.
--
-- BANDS are a stated convention, not a universal standard:
--   CV < 0.20   Low        hospitals bill this near-identically
--   0.20-0.50   Moderate
--   0.50-1.00   High
--   >= 1.00     Extreme    SD exceeds the mean
-- Chosen because they are the common bands in cost-variation work and they
-- separate this data sensibly. A different project may justify different
-- cut points -- change them here, in one place.
--
-- FLOORS: >=30 claims per hospital-condition pair (a 2-claim hospital
-- should not set the min or max), and >=20 qualifying hospitals per
-- condition (dispersion across 3 hospitals is not a distribution).
--
-- Results: sql/results/q1_hospital_variability_2020_2024.csv
-- =====================================================================

WITH claim_money AS (
    SELECT
        v.CLAIM_ID,
        MIN(v.ENCOUNTER_ID)  AS encounter_id,
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
-- stage 1: one cost-per-claim value per hospital x condition
per_hospital AS (
    SELECT
        cc.condition_code,
        e.ORGANIZATION_ID,
        COUNT(*)                       AS claims,
        SUM(m.billed) / COUNT(*)       AS cost_per_claim
    FROM claim_money m
    JOIN claim_condition cc ON m.CLAIM_ID = cc.CLAIM_ID
    JOIN SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.ENCOUNTERS e
      ON m.encounter_id = e.ENCOUNTER_ID
    WHERE cc.condition_code IS NOT NULL
    GROUP BY cc.condition_code, e.ORGANIZATION_ID
    HAVING COUNT(*) >= 30
),
-- stage 2: dispersion across hospitals, per condition
dispersion AS (
    SELECT
        condition_code,
        COUNT(*)                                  AS hospitals,
        SUM(claims)                               AS claims,
        AVG(cost_per_claim)                       AS mean_cpc,
        MEDIAN(cost_per_claim)                    AS median_cpc,
        STDDEV(cost_per_claim)                    AS sd_cpc,
        MIN(cost_per_claim)                       AS min_cpc,
        MAX(cost_per_claim)                       AS max_cpc,
        APPROX_PERCENTILE(cost_per_claim, 0.25)   AS p25_cpc,
        APPROX_PERCENTILE(cost_per_claim, 0.75)   AS p75_cpc
    FROM per_hospital
    GROUP BY condition_code
    HAVING COUNT(*) >= 20
),
scored AS (
    SELECT
        d.*,
        sd_cpc / NULLIF(mean_cpc, 0)                          AS cv,
        (p75_cpc - p25_cpc) / NULLIF(median_cpc, 0)           AS robust_cv
    FROM dispersion d
)
SELECT
    dd.DESCRIPTION                                   AS "Condition",
    s.condition_code                                 AS "Condition Code",
    s.hospitals                                      AS "Hospitals",
    s.claims                                         AS "Claims",
    ROUND(s.mean_cpc, 2)                             AS "Mean Cost per Claim",
    ROUND(s.median_cpc, 2)                           AS "Median Cost per Claim",
    ROUND(s.sd_cpc, 2)                               AS "SD",
    ROUND(s.cv, 3)                                   AS "CV",
    ROUND(s.robust_cv, 3)                            AS "Robust CV (IQR/median)",
    ROUND(s.min_cpc)                                 AS "Min",
    ROUND(s.max_cpc)                                 AS "Max",
    ROUND(s.max_cpc / NULLIF(s.min_cpc, 0), 1)       AS "Max/Min",
    CASE
        WHEN s.cv <  0.20 THEN '1 Low'
        WHEN s.cv <  0.50 THEN '2 Moderate'
        WHEN s.cv <  1.00 THEN '3 High'
        ELSE                   '4 Extreme'
    END                                              AS "Variability Band",
    -- CV says spread, quartiles say tight => a few outlier sites, not real spread
    IFF(s.cv >= 0.50 AND s.robust_cv < 0.30, TRUE, FALSE)
                                                     AS "Outlier Driven"
FROM scored s
JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY dd ON s.condition_code = dd.CODE
ORDER BY s.cv DESC;
