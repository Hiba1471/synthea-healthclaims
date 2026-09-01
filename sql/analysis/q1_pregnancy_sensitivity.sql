-- =====================================================================
-- SENSITIVITY TEST: does the condition ranking survive repricing pregnancy
-- to its real-world cost?
--
-- q1_condition_procedures.sql established pregnancy bills 8.6x the KFF 2022
-- figure ($161,988 here vs ~$18,865 real, large-employer claims, 2018-2020).
-- The report says the ranking and shares are "unaffected" by that gap. This
-- query is the test of that claim, not an assertion of it: every pregnancy
-- claim's BILLED_AMOUNT is divided by 8.6 (leaving visit count, timing and
-- every other condition untouched), and the condition ranking, the top-5 and
-- top-20 shares of diagnosed spend, and patient-level concentration are all
-- recomputed on the repriced total.
--
-- This is a same-shape repricing, not a real substitute for a true clinical-
-- claims dataset: it assumes each of the 11.1 prenatal claims scales down by
-- the same factor, which is a simplification, not a validated per-procedure
-- price correction.
--
-- Results: sql/results/q1_pregnancy_sensitivity_2020_2024.csv
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
-- Result: repricing pregnancy DOWN makes patient concentration go UP, not
-- down -- top 1% moves from 11.8% (unrepriced) to 15.4%, and the number of
-- patients needed to reach half of spend falls from 134,198 to 127,841.
-- Pregnancy spend was moderate-sized and spread across many patients, so
-- removing its inflation shifts relative weight toward the genuinely highest-
-- cost patients (cancer, kidney failure). Finding 4 is not merely robust to
-- the pregnancy pricing error -- it is conservative: the real concentration
-- is at least as strong as reported, arguably stronger.
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
