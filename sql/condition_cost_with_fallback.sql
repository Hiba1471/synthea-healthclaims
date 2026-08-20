-- =====================================================================
-- Which conditions are most expensive to treat, and is that concentrated
-- with particular payers?   2020-2024, WITH DIAGNOSIS2 FALLBACK.
--
-- Why the fallback: in this dataset DIAGNOSIS1 is not really a principal
-- diagnosis. Measured on a 1% sample, ~50.6% of it is copied from
-- ENCOUNTERS.REASONCODE and ~13.9% from ENCOUNTERS.CODE -- i.e. about
-- two-thirds is encounter metadata ("Well child visit", "Medication review
-- due"), not an illness. Only 46.7% of claims carry a real condition in
-- position 1. DIAGNOSIS2-8 are the opposite: zero procedure codes and
-- 59.8%-98% conditions.
--
-- So the rule is: take DIAGNOSIS1 when it IS a condition (a genuine
-- principal diagnosis, 46.7% of claims); otherwise fall back to
-- DIAGNOSIS2. That recovers 5,939,894 claims (8.7%) whose only real
-- diagnosis sits in position 2, lifting coverage 46.7% -> 55.4%.
--
-- Claims with no condition in either position (44.6%) are still excluded,
-- correctly: wellness visits, cleanings and screenings have no diagnosis.
--
-- ATTRIBUTION CAVEAT: position 2 is nominally a secondary diagnosis, so
-- charging a claim's full cost to it can overstate that condition. The
-- alternative is charging it to nothing, which is what the DIAGNOSIS1-only
-- version does. Compare against sql/condition_cost_clean.sql to see exactly
-- what the fallback moves.
-- =====================================================================

WITH claim_money AS (
    SELECT
        CLAIM_ID,
        PAYER_NAME,
        PAYER_TYPE,
        SUM(BILLED_AMOUNT)   AS billed,
        SUM(PAID_AMOUNT)     AS paid,
        SUM(PAID_BY_PATIENT) AS patient_paid
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN
    WHERE NOT IS_ADMIN_NOISE_CODE
      AND PROCEDURECODE IS NOT NULL
    GROUP BY CLAIM_ID, PAYER_NAME, PAYER_TYPE
),
claim_condition AS (
    -- one condition code per claim: position 1 if it is a real condition,
    -- else position 2, else the claim drops out
    SELECT
        c.CLAIM_ID,
        CASE WHEN d1.IS_CONDITION THEN c.DIAGNOSIS1
             WHEN d2.IS_CONDITION THEN c.DIAGNOSIS2
        END AS condition_code
    FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.CLAIMS c
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d1 ON c.DIAGNOSIS1 = d1.CODE
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d2 ON c.DIAGNOSIS2 = d2.CODE
)
SELECT
    d.CODE                                                        AS "Condition Code",
    d.DESCRIPTION                                                 AS "Condition Name",
    m.PAYER_NAME                                                  AS "Payer Name",
    m.PAYER_TYPE                                                  AS "Payer Type",
    '$' || TRIM(TO_VARCHAR(ROUND(SUM(m.billed)), '999,999,999,999'))
                                                                  AS "Total Billed",
    '$' || TRIM(TO_VARCHAR(ROUND(SUM(m.paid)),   '999,999,999,999'))
                                                                  AS "Total Paid",
    '$' || TRIM(TO_VARCHAR(ROUND(SUM(m.billed) / COUNT(*)), '999,999,999'))
                                                                  AS "Avg Cost per Claim",
    TRIM(TO_VARCHAR(ROUND(100 * SUM(m.patient_paid)
                          / NULLIF(SUM(m.paid), 0), 1), '9990.0')) || '%'
                                                                  AS "% Borne by Patient",
    TRIM(TO_VARCHAR(COUNT(*), '999,999,999'))                     AS "Number of Claims"
FROM claim_money m
JOIN claim_condition cc
    ON m.CLAIM_ID = cc.CLAIM_ID
JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d
    ON cc.condition_code = d.CODE
WHERE cc.condition_code IS NOT NULL
GROUP BY d.CODE, d.DESCRIPTION, m.PAYER_NAME, m.PAYER_TYPE
HAVING SUM(m.billed) > 0
ORDER BY SUM(m.billed) DESC;
