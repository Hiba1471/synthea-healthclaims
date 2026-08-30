-- =====================================================================
-- Q3 FOLLOW-UP: is the hospital spread utilisation, or composition again?
--
-- WHY THIS EXISTS. q3_price_vs_casemix.sql showed cost per visit is not price
-- (a median 7.8% of it reflects what a site charges). Q3 was then left saying
-- "what remains actionable is utilisation, not rates" -- an assertion, not a
-- finding. If price is flat, the difference must be quantity; but "quantity"
-- could mean either of two very different things:
--
--   UTILISATION   the same patients getting more done to them. Actionable.
--   COMPOSITION   different patients, or different parts of a care pathway.
--                 Not actionable, and not a fault of the hospital.
--
-- Two tests, both in this query.
--
-- TEST 1 -- do hospitals do different AMOUNTS for the same condition?
-- Almost never. Across 119 conditions with enough volume to compare, the spread
-- in procedures per claim between sites, (P75-P25)/median:
--
--   median condition   0.027      p75   0.116      p90   0.521
--
-- The typical condition is 0.027 -- hospitals do effectively identical amounts.
-- Only 12 of 119 exceed 0.5, and all but one are small: chronic heart failure
-- 4.116 ($339M, 86 sites), COPD 1.596 ($108M, 51 sites), emphysema 1.388
-- ($136M, 76 sites). Few sites means noisy quartiles, and under $600M between
-- them against $70.9B covered here.
--
-- The exception that matters is NORMAL PREGNANCY: variation 0.962 across 856
-- sites and $28.9B of spend. It is 84% of all the money sitting in
-- high-variation conditions, so if a utilisation lever exists anywhere, it is
-- there. Test 2 goes looking.
--
-- TEST 2 -- is pregnancy's spread real practice variation? No. Split its sites
-- into cheapest and dearest quarter and look at what they actually do:
--
--   cheapest quarter, $4,130/claim     dearest quarter, $17,315/claim
--     obstetric admission  35.7%         fetal heart auscultation  15.8%
--     childbirth           29.1%         uterine fundal height     15.8%
--     episiotomy            9.2%         prenatal visit            14.6%
--     epidural              7.2%         hemogram                   3.6%
--     induction of labor    6.2%         pregnancy test             2.7%
--     cesarean section      4.5%         fetal viability ultrasound 2.7%
--
-- The cheap sites DELIVER BABIES. The dear sites RUN ANTENATAL CLINICS. A site
-- following someone through nine months accumulates far more per claim than one
-- that sees them once for the birth. That is not the same work at different
-- intensity -- it is different halves of the pathway. Composition again.
--
-- THE TRAP. Sizing "excess over the median site" naively gives $17.3B on
-- pregnancy alone, 59.7% of its spend ($25.0B across the top ten conditions).
-- DO NOT PUT THAT NUMBER IN THE REPORT OR ANY CHART. It assumes every site
-- could reach the median, and Test 2 shows they cannot: an antenatal clinic
-- cannot reach a delivery unit's cost per claim, because it is not doing the
-- same thing. The figure is recorded here only so nobody recomputes it and
-- mistakes it for a savings opportunity.
--
-- WHAT THIS SETTLES. Every between-hospital difference Q3 has examined resolves
-- to composition -- what a site does -- and never to efficiency at doing it.
-- Combined with the price result, that removes the last candidate lever. See
-- the Q3 recommendation in DATA_ANALYSIS_CONTEXT.md, which now reports a scope
-- and four eliminations rather than an action.
--
-- Synthea models no practice variation, so this could not have come out any
-- other way. The METHOD transfers to real claims data; the FINDING does not.
--
-- Results: sql/results/q3_utilisation_or_composition_2020_2024.csv
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
