-- =====================================================================
-- Q1: what is actually billed on claims attributed to a condition? A
-- claim carries the diagnosis; procedures are line items on it, so this
-- is procedure-level detail behind the pricing-defect finding.
--
-- Result: Synthea prices ENCOUNTERS realistically but PROCEDURES at a
-- flat few thousand dollars regardless of complexity -- a fundal-height
-- check (a tape measure) bills $4,968, an allergy shot bills $11,122
-- against a real $50-200. Conditions whose pathway repeats many discrete
-- procedure codes are inflated hardest; conditions billed mainly through
-- encounters are roughly right. Rankings and ratios hold; totals do not.
-- Covers the two largest conditions -- add a code to the target list to
-- examine another.
-- =====================================================================

WITH target AS (
    SELECT 72892002  AS condition_code UNION ALL   -- Normal pregnancy   (#1 by spend)
    SELECT 419199007                                -- Allergy to substance (#2)
),
target_claims AS (
    SELECT c.CLAIM_ID, d.DESCRIPTION AS condition_name
    FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.CLAIMS c
    JOIN target t                                        ON c.DIAGNOSIS1 = t.condition_code
    JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY d    ON c.DIAGNOSIS1 = d.CODE
    WHERE d.IS_CONDITION
),
lines AS (
    SELECT
        tc.condition_name,
        COALESCE(dd.DESCRIPTION, '(code not in dictionary)') AS procedure_name,
        COALESCE(dd.CODE_CATEGORY, 'Unknown')                AS procedure_type,
        v.BILLED_AMOUNT
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_CLEAN v
    JOIN target_claims tc ON v.CLAIM_ID = tc.CLAIM_ID
    LEFT JOIN SYNTHEA_HEALTHCLAIMS.PUBLIC.CODE_DICTIONARY dd ON v.PROCEDURECODE = dd.CODE
    WHERE v.BILLED_AMOUNT > 0
)
SELECT
    condition_name                                         AS "Condition",
    procedure_name                                         AS "What was billed",
    procedure_type                                         AS "Kind of item",
    COUNT(*)                                               AS "Times billed",
    ROUND(SUM(BILLED_AMOUNT))                              AS "Total billed",
    ROUND(100 * SUM(BILLED_AMOUNT)
          / SUM(SUM(BILLED_AMOUNT)) OVER (PARTITION BY condition_name), 2)
                                                           AS "% of this condition's cost",
    ROUND(AVG(BILLED_AMOUNT), 2)                           AS "Average price each time"
FROM lines
GROUP BY condition_name, procedure_name, procedure_type
ORDER BY condition_name, SUM(BILLED_AMOUNT) DESC;
