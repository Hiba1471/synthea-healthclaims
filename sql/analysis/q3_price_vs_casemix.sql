-- =====================================================================
-- Q3 follow-up: is a hospital's cost per visit driven by its PRICES or
-- its CASE MIX? Repriced every procedure to its all-hospital average and
-- recomputed cost per visit; if the spread survives, it was never price.
--
-- Result: it survives almost entirely (15.8x spread actual vs. 15.2x
-- case-mix-only). A hospital's cost per visit is what it treats, not
-- what it charges -- Q1's "no negotiable price variation" conclusion was
-- right, and Q3's price-negotiation recommendation had no basis. Does
-- not weaken the concentration finding (86 sites still carry half the
-- spend); it changes the lever to which procedures sites perform.
--
-- CAVEAT: the 7.8% median gap is an ABSOLUTE-VALUE median. The signed
-- median is only 3.0% (41% of sites price below the case-mix benchmark),
-- so state which one is being quoted -- they answer different questions.
-- =====================================================================

WITH line AS (
    SELECT v.ENCOUNTER_ID, v.PATIENT_ID, v.PROCEDURECODE, v.BILLED_AMOUNT
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN v
    WHERE NOT v.IS_ADMIN_NOISE_CODE
      AND v.PROCEDURECODE IS NOT NULL
      AND v.BILLED_AMOUNT > 0
),
-- one benchmark price per procedure, across every hospital
proc_avg AS (
    SELECT PROCEDURECODE, AVG(BILLED_AMOUNT) AS avg_price
    FROM line GROUP BY PROCEDURECODE
),
sited AS (
    SELECT o.NAME || ' (' || o.CITY || ', ' || o.STATE || ')' AS hospital,
           l.ENCOUNTER_ID, l.PATIENT_ID, l.BILLED_AMOUNT, p.avg_price
    FROM line l
    JOIN SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.ENCOUNTERS e
      ON l.ENCOUNTER_ID = e.ENCOUNTER_ID
    JOIN SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.ORGANIZATIONS o
      ON e.ORGANIZATION_ID = o.ORGANIZATION_ID
    JOIN proc_avg p ON l.PROCEDURECODE = p.PROCEDURECODE
),
by_site AS (
    SELECT hospital,
           COUNT(DISTINCT PATIENT_ID)                        AS patients,
           COUNT(DISTINCT ENCOUNTER_ID)                      AS visits,
           SUM(BILLED_AMOUNT) / COUNT(DISTINCT ENCOUNTER_ID) AS actual_per_visit,
           SUM(avg_price)     / COUNT(DISTINCT ENCOUNTER_ID) AS casemix_per_visit
    FROM sited
    GROUP BY hospital
    -- same floor as q3_hospital_cost_intensity, so the two files line up
    HAVING COUNT(DISTINCT PATIENT_ID) >= 1000
)
SELECT
    hospital                                            AS "Hospital",
    patients                                            AS "Patients",
    visits                                              AS "Visits",
    ROUND(actual_per_visit)                             AS "Actual cost per visit",
    ROUND(casemix_per_visit)                            AS "Cost per visit if all prices were equal",
    ROUND(100 * (actual_per_visit - casemix_per_visit)
          / NULLIF(actual_per_visit, 0), 1)             AS "% of it that is pricing, not case mix"
FROM by_site
ORDER BY actual_per_visit DESC;
