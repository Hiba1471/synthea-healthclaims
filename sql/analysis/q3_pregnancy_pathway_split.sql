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
-- SPLIT the 856 sites into cheapest and dearest quarter by cost per claim:
--
--                              cheapest quarter    dearest quarter
--   women                            64,642             87,051
--   visits per woman                    1.3                9.9
--   claims per woman                   1.33               9.95
--   cost per claim                   $4,130            $17,314
--   cost per woman                   $5,475           $172,234
--   GAVE BIRTH AT THAT SITE           95.5%               7.1%
--   share of spend on the birth        29.7%               0.1%
--
-- The last two rows are the answer. At the cheap sites 95.5% of the women
-- deliver there and the birth is 29.7% of the billing: these are DELIVERY
-- UNITS. At the dear sites only 7.1% deliver and the birth is 0.1% of billing:
-- these are ANTENATAL CLINICS, seeing a woman ten times across nine months
-- while she gives birth somewhere else entirely.
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
    SELECT o.NAME AS hospital, v.CLAIM_ID, v.PATIENT_ID, v.PROCEDURECODE, v.BILLED_AMOUNT
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
SELECT CASE b.q WHEN 1 THEN '1 cheapest quarter' WHEN 4 THEN '4 dearest quarter' END AS band,
       COUNT(DISTINCT p.PATIENT_ID)                                   AS women,
       ROUND(100.0 * SUM(IFF(LOWER(d.DESCRIPTION) IN ('childbirth','cesarean section'),
                             p.BILLED_AMOUNT, 0)) / SUM(p.BILLED_AMOUNT), 1) AS pct_spend_on_the_birth,
       ROUND(100.0 * COUNT(DISTINCT IFF(LOWER(d.DESCRIPTION) IN ('childbirth','cesarean section'),
                             p.PATIENT_ID, NULL)) / COUNT(DISTINCT p.PATIENT_ID), 1) AS pct_women_who_gave_birth_here
FROM preg p
JOIN banded b ON p.hospital = b.hospital
LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d ON p.PROCEDURECODE = d.CODE
WHERE b.q IN (1,4)
GROUP BY b.q ORDER BY band;
