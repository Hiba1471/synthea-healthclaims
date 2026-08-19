-- =====================================================================
-- Which conditions are most expensive to treat, and is that concentrated
-- with particular payers?  2020-2024.
--
-- Rewritten against the two curated artifacts, which is why this is ~30
-- lines instead of ~90:
--   ENERGY_PIPELINE.PUBLIC.V_CLAIMS_TX_CLEAN  -- correct money columns,
--       payer already collapsed, date window already applied
--   ENERGY_PIPELINE.PUBLIC.CODE_DICTIONARY    -- every code resolves to a
--       name, with IS_CONDITION separating real diagnoses from visit types,
--       paperwork and social determinants
--
-- Attribution is CLAIMS.DIAGNOSIS1 (one primary diagnosis per claim, 0%
-- null). Joining CONDITIONS on ENCOUNTER_ID instead would fan out and
-- multiply the spend.
-- =====================================================================

WITH claim_money AS (
    SELECT
        CLAIM_ID,
        PAYER_NAME,
        PAYER_TYPE,
        SUM(BILLED_AMOUNT)   AS billed,
        SUM(PAID_AMOUNT)     AS paid,
        SUM(PAID_BY_PATIENT) AS patient_paid
    FROM ENERGY_PIPELINE.PUBLIC.V_CLAIMS_TX_CLEAN
    WHERE NOT IS_ADMIN_NOISE_CODE
      AND PROCEDURECODE IS NOT NULL
    GROUP BY CLAIM_ID, PAYER_NAME, PAYER_TYPE
)
SELECT
    d.CODE                                                        AS "Condition Code",
    d.DESCRIPTION                                                 AS "Condition Name",
    d.CODE_CATEGORY                                               AS "Code Category",
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
JOIN SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.CLAIMS c
    ON m.CLAIM_ID = c.CLAIM_ID
JOIN ENERGY_PIPELINE.PUBLIC.CODE_DICTIONARY d
    ON c.DIAGNOSIS1 = d.CODE
WHERE d.IS_CONDITION            -- excludes visit types, paperwork, employment status
GROUP BY d.CODE, d.DESCRIPTION, d.CODE_CATEGORY, m.PAYER_NAME, m.PAYER_TYPE
HAVING SUM(m.billed) > 0
ORDER BY SUM(m.billed) DESC;
