-- =====================================================================
-- Q1: what is actually being billed under a condition?
--
-- Written to test whether the headline conditions are realistically priced.
-- They are not, and this query is how that was found.
--
-- HOW THE LINKAGE WORKS: a procedure is not "owned" by a condition. The
-- CLAIM carries the diagnosis; the procedures are line items hanging off
-- that claim. So this shows what was billed ON CLAIMS ATTRIBUTED TO each
-- condition. The same procedure (a blood count, say) appears under many
-- conditions.
--
-- WHAT IT REVEALS: Synthea prices ENCOUNTERS realistically and PROCEDURES at
-- a flat few thousand dollars regardless of complexity.
--
--   prenatal visit                        $119   correct
--   childbirth                            $488   the delivery itself
--   caesarean section                   $7,943   major surgery, about right
--   evaluation of uterine fundal height $4,968   a tape measure
--   auscultation of the fetal heart     $4,967   a doppler on the abdomen
--   subcutaneous immunotherapy         $11,122   an allergy shot (real: $50-200)
--
-- The fundal-height check bills 40x the visit containing it. 23 routine
-- prenatal labs all sit at a flat $1,890-1,901 against a real $10-30 each.
-- So conditions whose pathway repeats many discrete procedure codes are
-- inflated hardest; conditions billed mainly through encounters are roughly
-- right. Rankings and ratios hold; absolute totals do not.
--
-- Covers the two largest conditions. To examine another, add its code to
-- the target list.
--
-- Results: sql/results/q1_pregnancy_procedures_2020_2024.csv
--          sql/results/q1_allergy_procedures_2020_2024.csv
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
