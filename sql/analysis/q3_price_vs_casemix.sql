-- =====================================================================
-- Q3 FOLLOW-UP: is a hospital's cost per visit its PRICES or its CASE MIX?
--
-- WHY THIS EXISTS. Q3 concluded that cost per patient tracks cost per visit
-- (Spearman +0.81) more closely than visit frequency (+0.65), and recommended
-- price negotiation across the broad middle of hospitals on that basis. But the
-- Q1 subsection "Does cost vary by payer or hospital?" says the opposite thing
-- about prices: ADJUSTMENTS is 0 on all 887M rows, there are no negotiated
-- rates, and of the ten highest-spend conditions only two show real spread
-- between typical hospitals. Both cannot be right.
--
-- THE TEST. Compute each site's actual cost per visit, then recompute it with
-- every procedure repriced to its all-hospital average. If the spread survives
-- repricing, it was never about price -- it is about which procedures the site
-- performs.
--
-- THE ANSWER, over the 730 sites with >=1,000 patients:
--
--   actual cost per visit             $1,013 - $16,030     15.8x spread
--   case-mix only, prices equalised   $1,105 - $16,805     15.2x spread
--   median |actual - casemix| / actual, across sites        7.8%
--
-- THE 7.8% IS AN ABSOLUTE-VALUE MEDIAN -- state it that way, not as "7.8% of
-- cost is price." The signed column below runs -29.8% to +27.0%, and the
-- median of the SIGNED values is only 3.0%, not 7.8%: 298 of 730 sites (41%)
-- have a NEGATIVE value, meaning their real prices for the procedures they
-- perform run BELOW the all-facility average for that same case mix. Taking
-- the absolute value is the right choice for "how much of cost-per-visit is
-- explained by a site's own pricing, as opposed to what it treats" -- a site
-- priced 10% under the benchmark is explained by price exactly as much as one
-- priced 10% over it -- but it means 7.8% is a typical MAGNITUDE of deviation
-- in either direction, not a typical markup, and it is not the same number as
-- the signed median. Report both if the distinction matters to the reader.
--
-- (On the wider 1,505-site population at a >=1,000-visit floor the same test
-- gives 29.9x against 24.1x, correlation 0.974, mean gap 9.24% -- the same
-- conclusion. NOT BACKED BY A SAVED RESULT FILE, unlike everything else in
-- this project: no query for the 1,505-site run exists in sql/analysis/, so
-- this line cannot be re-verified from the repo, and whether "mean gap" here
-- is signed or absolute is not recorded. Treat it as a secondary robustness
-- note, not as a citable figure, until it is rerun and saved.)
--
-- Equalising every price in the dataset removes almost none of the spread. A
-- hospital's cost per visit is what it treats, not what it charges. Q1 was
-- right and Q3's price-negotiation recommendation had no basis: there is no
-- meaningful price variation to negotiate away, and the +0.81 correlation with
-- "cost per visit" is a correlation with case-mix intensity wearing a price
-- label.
--
-- This does not weaken the concentration finding. 86 sites still carry half the
-- spend. It changes what can be done about them -- the question becomes which
-- procedures are being performed and whether they are necessary, not what they
-- cost each.
--
-- Results: sql/results/q3_price_vs_casemix_2020_2024.csv
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
