-- =====================================================================
-- SENSITIVITY TEST, EXTENDED: does the condition ranking and patient
-- concentration survive correcting ALL confidently-documented pricing
-- defects, not just pregnancy's?
--
-- Same bounded "what if" method as q1_pregnancy_sensitivity.sql, extended to
-- eleven conditions instead of one. This is NOT a corrected dataset and does
-- not touch any view or table: every condition below has its BILLED_AMOUNT
-- divided by a single factor for claims attributed to it, leaving visit
-- count, timing and every other condition untouched, and the results are
-- read as a stress test of the report's rankings, not as new ground truth.
--
-- WHICH ELEVEN, AND WHY ONLY THESE. Of the twenty highest-cost conditions
-- checked against a real-world benchmark (DATA_ANALYSIS_CONTEXT.md, "All ten
-- of the highest-cost conditions, benchmarked one at a time" and its top-20
-- extension), eleven have a single, well-grounded external benchmark and a
-- claims-per-patient pattern consistent with one or a small, countable number
-- of episodes -- a clean correction factor can be defended for each. Five
-- more (cardiac imaging findings, small cell lung cancer, child ADHD,
-- ischemic heart disease, dependent drug abuse) have claims-per-patient
-- patterns implying multi-year aggregated care with no clean annual cadence
-- to anchor an annualization on, the way dialysis's fixed three-times-weekly
-- schedule did -- correcting those would require an assumption this project
-- cannot defend, so they are left untouched here. Four (CKD-4, ESRD, breast
-- cancer, COVID-19) were checked and found NOT inflated (two are actually
-- under the real-world benchmark), so they are also left untouched.
--
-- Divisor for each (this data's figure / midpoint of the named benchmark):
--   Normal pregnancy              72892002   / 8.587   (KFF 2022)
--   Allergy to substance          419199007  / 88.976  ($11,122/shot vs $50-200)
--   Gingivitis                    66383009   / 12.542  (scaling & root planing)
--   Gingival disease               18718003  / 7.522   (scaling & root planing)
--   NSCLC stage 1                 424132000  / 11.038  (4-yr surgical resection)
--   Polyp of colon                68496003   / 19.736  (colonoscopy + polypectomy)
--   Laceration - injury           312608009  / 5.285   (ER laceration repair)
--   Primary dental caries         109570002  / 16.564  (per filling)
--   Acute bronchitis              10509002   / 9.252   (doctor visit)
--   Stroke                        230690007  / 3.836   (first-year cost)
--   Acute infective cystitis      307426000  / 23.590  (uncomplicated UTI)
--
-- Results: sql/results/q1_multi_condition_sensitivity_2020_2024.csv
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
totals AS (SELECT SUM(total_billed) AS diagnosed_total FROM by_condition)
SELECT 'Condition ranking, 11-condition repricing' AS test,
       r.condition_name,
       r.rank_repriced,
       ROUND(r.total_billed) AS billed_repriced,
       ROUND(100.0 * r.total_billed / t.diagnosed_total, 2) AS pct_of_diagnosed_repriced
FROM ranked r CROSS JOIN totals t
WHERE r.rank_repriced <= 20
ORDER BY r.rank_repriced;

-- =====================================================================
-- PART 2: patient-level spend concentration (Finding 4 / q3_concentration)
-- under the same 11-condition correction. Same window-function shape as
-- part 2 of q1_pregnancy_sensitivity.sql (the correlated-subquery version
-- does not finish against 1.26M patients).
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
