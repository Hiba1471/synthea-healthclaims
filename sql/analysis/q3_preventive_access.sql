-- =====================================================================
-- Q3 FOLLOW-UP: do high-spend members get less preventive care?
--
-- Asked because it is the obvious next question after "spend concentrates in
-- places, not people" -- if a small group of members is not expensive, perhaps
-- a large group is under-served. The answer is that this dataset cannot support
-- the question, and this query exists so that conclusion is traceable rather
-- than asserted.
--
-- THREE REASONS, in order of how badly each one kills it:
--
-- 1. THERE IS NO ACCESS GAP TO MEASURE. Wellness encounters reach 1,259,199 of
--    1,259,375 patients -- 99.99%. Fewer than 0.03% of members in any spend
--    decile have none at all.
--
-- 2. THE AMOUNT VARIES, BUT NOT WITH SPEND. Average wellness visits by spend
--    decile trace an arch, not a slope:
--
--      decile  1     2     3     4     5     6     7     8     9    10
--      visits  3.94  4.91  4.94  4.82  4.65  4.50  4.35  4.31  3.80  3.84
--      age     19    24    28    34    40    46    50    51    43    40
--
--    The top deciles look lightly under-served against the peak, but they are
--    not comparable populations: average age climbs to 51 by decile 8 then
--    FALLS BACK to 40, because normal pregnancy is 39.8% of spend and puts
--    women of childbearing age at the top of the ranking. The dip is who is in
--    the group, not what they received. Reporting it as an access finding would
--    repeat the composition error that took four attempts to clear out of Q3.
--
-- 3. SYNTHEA CANNOT ANSWER IT IN PRINCIPLE. Wellness visits are generated on a
--    fixed protocol schedule by age. Nothing in the simulation models a member
--    skipping care, facing a barrier, or declining a screening. No phrasing of
--    the question is answerable here.
--
-- The answerable neighbour is Q2: does cost-sharing fall hardest on routine
-- care? It does, and that is a benefit-design question rather than a behaviour
-- one. See q2_patient_cost_by_care_type.sql.
--
-- Results: sql/results/q3_preventive_access_2020_2024.csv
-- =====================================================================

WITH spend AS (
    SELECT PATIENT_ID, SUM(BILLED_AMOUNT) AS billed
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
    WHERE NOT IS_ADMIN_NOISE_CODE
      AND PROCEDURECODE IS NOT NULL
      AND BILLED_AMOUNT > 0
    GROUP BY PATIENT_ID
),
wellness AS (
    SELECT PATIENT_ID, COUNT(*) AS visits
    FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.ENCOUNTERS
    WHERE ENCOUNTERCLASS = 'wellness'
      AND ENCOUNTER_START >= '2020-01-01'
      AND ENCOUNTER_START <  '2025-01-01'
    GROUP BY PATIENT_ID
),
banded AS (
    SELECT s.PATIENT_ID, s.billed,
           COALESCE(w.visits, 0)                  AS wellness_visits,
           NTILE(10) OVER (ORDER BY s.billed)     AS decile
    FROM spend s
    LEFT JOIN wellness w ON s.PATIENT_ID = w.PATIENT_ID
)
SELECT
    b.decile                                              AS "Spend decile",
    COUNT(*)                                              AS "Members",
    ROUND(AVG(b.billed))                                  AS "Average billed",
    ROUND(AVG(DATEDIFF('year', p.BIRTHDATE, '2022-07-01'))) AS "Average age",
    ROUND(AVG(b.wellness_visits), 2)                      AS "Wellness visits each",
    ROUND(100.0 * AVG(IFF(b.wellness_visits = 0, 1, 0)), 2)
                                                          AS "% with no wellness visit"
FROM banded b
JOIN SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.PATIENTS p
  ON b.PATIENT_ID = p.PATIENT_ID
GROUP BY b.decile
ORDER BY b.decile;
