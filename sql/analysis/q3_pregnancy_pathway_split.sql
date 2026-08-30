-- =====================================================================
-- Q3 FOLLOW-UP: why does "normal pregnancy" cost 4x more per claim at
--               some hospitals than others?
--
-- Normal pregnancy is the one condition where hospitals look genuinely
-- different: variation 0.962 across 856 sites against a typical 0.027, on
-- $28.9B of spend (q3_utilisation_or_composition.sql). If a utilisation lever
-- exists anywhere in this dataset, it is here. This query establishes that it
-- is not a lever, and the evidence is stronger than the procedure-mix split
-- recorded in that file's header.
--
-- SPLIT the 856 sites into four equal groups of 214 by cost per claim. All four
-- are returned, and the shape is the finding:
--
--   group   sites    women   per claim  visits/woman  % of $ on birth  % gave birth there
--     1      214    65,776      $4,130       1.3            29.7             95.5
--     2      214    46,781      $5,263       1.3            30.1             95.8
--     3      214   101,424     $13,640       9.6             0.2             12.2
--     4      214    83,838     $17,314      10.3             0.1              6.8
--
-- THIS IS NOT A GRADIENT, IT IS A CLIFF, and that is what settles the question.
-- Groups 1 and 2 are indistinguishable from each other: ~1.3 visits, ~95% of
-- women giving birth on site, the birth being ~30% of billing. Groups 3 and 4
-- are likewise a pair: ~10 visits, 7-12% giving birth on site, the birth being
-- 0.1-0.2% of billing. Nothing sits between them -- no site runs 5 visits, none
-- has half its women delivering there.
--
-- So 428 sites are DELIVERY UNITS and 428 are ANTENATAL CLINICS, seeing a woman
-- ten times across nine months while she gives birth somewhere else entirely.
-- Two populations sharing one billing code, not a spread of efficiency. Waste
-- would show as a smooth distribution; this is bimodal.
--
-- Returning only the two extremes (the first version of this query) understated
-- the case, because two ends of any ranking always look different. The middle
-- groups are what prove there is no middle.
--
-- So "cost per pregnancy claim" compares one birth against nine months of
-- check-ups. The sites are not doing the same work at different prices or
-- different intensities -- they are doing different halves of the pathway, for
-- largely different women. Nothing here can be negotiated or reviewed down.
--
-- WHY THE SIMPLER OVERLAP TEST MISLEADS. Asking how many women appear at both
-- kinds of site returns only 6.3%, which looks like it refutes the pathway
-- reading. It does not: that test only looks at the top and bottom quarters, so
-- a woman with check-ups in the dearest quarter and a delivery in the second or
-- third counts as "dear only". Asking whether she gave birth AT THAT SITE is
-- the question that actually separates the two groups.
--
-- Prices here are Synthea's and are not realistic in absolute terms ($172,234
-- for antenatal care is a generator artefact). The RATIO and the composition
-- split are the findings; the magnitudes are not.
--
-- Results: sql/results/q3_pregnancy_pathway_split_2020_2024.csv
-- =====================================================================

WITH claim_condition AS (
    SELECT c.CLAIM_ID,
           CASE WHEN d1.IS_CONDITION THEN c.DIAGNOSIS1
                WHEN d2.IS_CONDITION THEN c.DIAGNOSIS2 END AS condition_code
    FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.CLAIMS c
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d1 ON c.DIAGNOSIS1 = d1.CODE
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d2 ON c.DIAGNOSIS2 = d2.CODE
),
preg AS (
    SELECT o.NAME || ' (' || o.CITY || ')' AS hospital, v.CLAIM_ID, v.PATIENT_ID, v.ENCOUNTER_ID,
           v.PROCEDURECODE, v.BILLED_AMOUNT
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN v
    JOIN claim_condition cc ON v.CLAIM_ID = cc.CLAIM_ID
    JOIN SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.ENCOUNTERS e ON v.ENCOUNTER_ID = e.ENCOUNTER_ID
    JOIN SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.ORGANIZATIONS o ON e.ORGANIZATION_ID = o.ORGANIZATION_ID
    WHERE cc.condition_code = 72892002
      AND NOT v.IS_ADMIN_NOISE_CODE AND v.PROCEDURECODE IS NOT NULL AND v.BILLED_AMOUNT > 0
),
site AS (SELECT hospital, SUM(BILLED_AMOUNT)/COUNT(DISTINCT CLAIM_ID) pc
         FROM preg GROUP BY hospital HAVING COUNT(DISTINCT CLAIM_ID) >= 30),
banded AS (SELECT hospital, NTILE(4) OVER (ORDER BY pc) q FROM site)
SELECT b.q                                                            AS "Quarter, cheapest to dearest",
       COUNT(DISTINCT p.hospital)                                     AS "Hospitals",
       COUNT(DISTINCT p.PATIENT_ID)                                   AS "Women",
       ROUND(SUM(p.BILLED_AMOUNT) / COUNT(DISTINCT p.CLAIM_ID))       AS "Cost per claim",
       ROUND(COUNT(DISTINCT p.ENCOUNTER_ID) * 1.0
             / COUNT(DISTINCT p.PATIENT_ID), 1)                       AS "Visits per woman",
       ROUND(100.0 * SUM(IFF(LOWER(d.DESCRIPTION) IN ('childbirth','cesarean section'),
                             p.BILLED_AMOUNT, 0)) / SUM(p.BILLED_AMOUNT), 1) AS "% of spend on the birth",
       ROUND(100.0 * COUNT(DISTINCT IFF(LOWER(d.DESCRIPTION) IN ('childbirth','cesarean section'),
                             p.PATIENT_ID, NULL)) / COUNT(DISTINCT p.PATIENT_ID), 1) AS "% who gave birth there"
FROM preg p
JOIN banded b ON p.hospital = b.hospital
LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d ON p.PROCEDURECODE = d.CODE
GROUP BY b.q ORDER BY b.q;
