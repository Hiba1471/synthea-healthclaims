-- =====================================================================
-- Sensitivity test: does the condition ranking survive repricing
-- pregnancy to its real-world cost (8.6x cheaper, per KFF 2022 --
-- q1_condition_procedures.sql)? Divides every pregnancy claim's
-- BILLED_AMOUNT by 8.6, leaving visit count and every other condition
-- untouched, then recomputes the ranking, top-5/top-20 shares and
-- patient-level concentration. A same-shape repricing, not a validated
-- per-procedure correction -- it assumes all prenatal claims scale down
-- by the same factor.
-- =====================================================================

WITH claim_money AS (
    SELECT
        CLAIM_ID,
        MIN(PATIENT_ID)      AS patient_id,
        SUM(BILLED_AMOUNT)   AS billed
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
    WHERE NOT IS_ADMIN_NOISE_CODE
      AND PROCEDURECODE IS NOT NULL
    GROUP BY CLAIM_ID
),
claim_condition AS (
    SELECT
        c.CLAIM_ID,
        CASE WHEN d1.IS_CONDITION THEN c.DIAGNOSIS1
             WHEN d2.IS_CONDITION THEN c.DIAGNOSIS2
        END AS condition_code
    FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.CLAIMS c
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d1 ON c.DIAGNOSIS1 = d1.CODE
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d2 ON c.DIAGNOSIS2 = d2.CODE
),
repriced AS (
    SELECT
        cc.condition_code,
        m.patient_id,
        IFF(cc.condition_code = '72892002', m.billed / 8.6, m.billed) AS billed
    FROM claim_money m
    JOIN claim_condition cc ON m.CLAIM_ID = cc.CLAIM_ID
    WHERE cc.condition_code IS NOT NULL
),
by_condition AS (
    SELECT d.CODE AS condition_code, d.DESCRIPTION AS condition_name,
           SUM(r.billed) AS total_billed
    FROM repriced r
    JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d ON r.condition_code = d.CODE
    GROUP BY d.CODE, d.DESCRIPTION
    HAVING SUM(r.billed) > 0
),
ranked AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY total_billed DESC) AS rank_repriced
    FROM by_condition
),
totals AS (SELECT SUM(total_billed) AS diagnosed_total FROM by_condition),
by_patient AS (
    SELECT patient_id, SUM(billed) AS patient_billed
    FROM repriced
    GROUP BY patient_id
),
patient_ranked AS (
    SELECT patient_billed,
           PERCENT_RANK() OVER (ORDER BY patient_billed) AS pctile
    FROM by_patient
)
SELECT 'Condition ranking, repriced' AS test,
       r.condition_name,
       r.rank_repriced,
       ROUND(r.total_billed) AS billed_repriced,
       ROUND(100.0 * r.total_billed / t.diagnosed_total, 2) AS pct_of_diagnosed_repriced
FROM ranked r CROSS JOIN totals t
WHERE r.rank_repriced <= 20
ORDER BY r.rank_repriced;

-- =====================================================================
-- PART 2: does patient-level spend concentration (Finding 4 / q3_concentration)
-- survive the same repricing? Same 8.6x correction applied to every pregnancy
-- claim, then the same top-1%/5%/10% and "how many patients for half of spend"
-- measures as q3_concentration.sql, recomputed with a window function rather
-- than the correlated-subquery version this started as (which did not finish
-- in 10 minutes against 1.26M patients -- keep the window-function shape if
-- this is ever rerun).
--
-- Result: repricing pregnancy ALONE DOWN makes patient concentration go UP,
-- not down -- top 1% moves from 11.8% (unrepriced) to 15.4%, and the number
-- of patients needed to reach half of spend falls from 134,198 to 127,841.
-- Pregnancy spend was moderate-sized and spread across many patients, so
-- removing its inflation shifts relative weight toward the genuinely highest-
-- cost patients (cancer, kidney failure).
--
-- THIS DOES NOT GENERALISE. q1_multi_condition_sensitivity.sql runs the same
-- test correcting eleven confidently-inflated conditions together, not just
-- pregnancy, and finds the OPPOSITE movement: top 1% comes back down to
-- 12.5%, close to the as-billed 11.8%. Conditions besides pregnancy that are
-- also inflated (allergy, dental, colon polyp, bronchitis, UTI) are
-- themselves broadly spread across many patients, so correcting them too
-- pulls concentration back down rather than compounding test 1's rise. Do
-- not describe Finding 4 as "conservative" or "at least as strong as
-- reported" on the strength of this single-condition test alone -- the
-- direction of this specific effect depends on how many conditions are
-- corrected, and is not settled by either test on its own.
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
    SELECT m.CLAIM_ID, m.patient_id,
           IFF(cc.condition_code = '72892002', m.billed / 8.6, m.billed) AS billed
    FROM claim_money m LEFT JOIN claim_condition cc ON m.CLAIM_ID = cc.CLAIM_ID
),
by_patient AS (SELECT patient_id, SUM(billed) AS patient_billed FROM repriced GROUP BY patient_id),
ranked AS (
    SELECT patient_billed,
           ROW_NUMBER() OVER (ORDER BY patient_billed DESC) AS rk,
           SUM(patient_billed) OVER (ORDER BY patient_billed DESC
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total,
           COUNT(*) OVER () AS n,
           SUM(patient_billed) OVER () AS tot
    FROM by_patient
)
SELECT
  MIN(n)                                                       AS "Patients",
  ROUND(MIN(IFF(rk = CEIL(0.01*n), running_total/tot*100, NULL)), 2) AS "Priciest 1%, repriced",
  ROUND(MIN(IFF(rk = CEIL(0.05*n), running_total/tot*100, NULL)), 2) AS "Priciest 5%, repriced",
  ROUND(MIN(IFF(rk = CEIL(0.10*n), running_total/tot*100, NULL)), 2) AS "Priciest 10%, repriced",
  MIN(IFF(running_total/tot >= 0.5, rk, NULL))                  AS "= this many for half, repriced"
FROM ranked;
