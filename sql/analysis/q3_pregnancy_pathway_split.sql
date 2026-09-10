-- =====================================================================
-- Q3 follow-up: why does normal pregnancy cost 4x more per claim at some
-- hospitals than others -- the one condition with real cross-site
-- variation (q3_visit_frequency_vs_case_mix.sql)? Splits the 856 sites
-- into four equal groups by cost per claim.
--
-- Result: not a gradient, a cliff. Groups 1-2 look identical (~1.3
-- visits/woman, ~95% deliver on site, birth is ~30% of billing); groups
-- 3-4 look identical to each other but nothing like 1-2 (~10 visits,
-- 7-12% deliver on site, birth is ~0.1% of billing). 428 sites are
-- delivery units, 428 are antenatal clinics billing nine months of
-- check-ups for a birth that happens elsewhere. Two populations sharing
-- one billing code, not a spread of efficiency -- nothing here is
-- negotiable. Dollar magnitudes are Synthea generator artefacts; the
-- ratio and the bimodal split are the findings.
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
