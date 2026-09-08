-- =====================================================================
-- CARE TYPE REPORT, rebuilt on V_CLAIMS_TX_WITH_CARETYPE, with a built-in
-- comparison against the figures the HTML report and dashboard publish.
--
-- WHY THIS EXISTS. The report at dashboard/analysis_report.html and the
-- dashboards are built from q2_patient_cost_by_care_type.sql, which resolves
-- care type inside the query. The Power BI report reads CARE_TYPE off the
-- view instead. Those are two different code paths to the same number, and
-- nothing so far has proved they agree. This file proves it, or shows exactly
-- where they don't -- in Snowflake, without exporting anything.
--
-- Run the whole file. PART 1 is the report. PART 2 is the check.
--
-- WHAT MUST MATCH, AND WHY IT SHOULD.
--   Attribution: both resolve the condition from CLAIMS.DIAGNOSIS1, falling
--     back to DIAGNOSIS2, through CODE_DICTIONARY.IS_CONDITION.
--   Ladder: the view carries the same 14-branch CASE in the same order.
--   Scope: the view bakes in NOT IS_ADMIN_NOISE_CODE AND PROCEDURECODE IS NOT
--     NULL, which is what the analysis query applies itself.
--   Grain: the analysis sums to CLAIM_ID first, the view is transaction-line.
--     Summing money over lines equals summing it over claims, so totals agree.
--
-- THE ONE DELIBERATE DIFFERENCE. The view LEFT JOINs the classification, so
-- claims with no resolvable diagnosis survive as 'No diagnosis on claim'
-- (~$26.4B). The analysis INNER JOINs and drops them. PART 1 therefore
-- filters that bucket out to compare like with like -- it is reported on its
-- own line at the bottom rather than hidden.
--
-- Denominator note: "% of the bill members pay" is member-paid over total
-- PAID, not over billed, matching q2_patient_cost_by_care_type.sql. In this
-- dataset collection is 100% so the two coincide, but the paid-based figure is
-- the one that survives contact with real claims.
-- =====================================================================

-- ---------------------------------------------------------------------
-- PART 1: the report
-- ---------------------------------------------------------------------
SELECT
    CARE_TYPE                                                  AS "Type of care",
    COUNT(DISTINCT PRIMARY_CONDITION)                          AS "Conditions grouped here",
    ROUND(SUM(BILLED_AMOUNT))                                  AS "Total bill",
    ROUND(SUM(PAID_BY_PATIENT))                                AS "Paid by members over 5 years",
    ROUND(SUM(PAID_BY_PAYER))                                  AS "Paid by insurers",
    ROUND(100 * SUM(PAID_BY_PATIENT)
          / NULLIF(SUM(PAID_AMOUNT), 0), 1)                    AS "% of the bill members pay",
    COUNT(DISTINCT PATIENT_ID)                                 AS "People affected",
    ROUND(SUM(BILLED_AMOUNT)
          / NULLIF(COUNT(DISTINCT PATIENT_ID), 0))             AS "Total cost per person",
    ROUND(SUM(PAID_BY_PATIENT)
          / NULLIF(COUNT(DISTINCT PATIENT_ID), 0))             AS "Of that, paid by the person",
    -- the same split by line of business, since the blended figure hides a gap
    ROUND(100 * SUM(IFF(PAYER_TYPE = 'Commercial', PAID_BY_PATIENT, 0))
          / NULLIF(SUM(IFF(PAYER_TYPE = 'Commercial', PAID_AMOUNT, 0)), 0), 1)
                                                               AS "% members pay - Commercial",
    ROUND(100 * SUM(IFF(PAYER_TYPE = 'Government', PAID_BY_PATIENT, 0))
          / NULLIF(SUM(IFF(PAYER_TYPE = 'Government', PAID_AMOUNT, 0)), 0), 1)
                                                               AS "% members pay - Government"
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
WHERE CARE_TYPE <> 'No diagnosis on claim'
GROUP BY CARE_TYPE
ORDER BY SUM(BILLED_AMOUNT) DESC;


-- ---------------------------------------------------------------------
-- PART 2: does it match the published report?
--
-- The expected side is sql/results/q2_patient_cost_by_care_type_2020_2024.csv
-- verbatim -- the same file dashboard/analysis_report.html and both dashboards
-- are built from. Every row should come back PASS.
--
-- Billed and member-paid are compared as exact rounded dollars. Share is
-- compared to 0.1pp, which is the precision the published file carries.
-- "People affected" is compared with a 0.5% tolerance, NOT exactly: the
-- analysis counts a member once per care type off claim-grain rows, and if
-- the view's line grain ever changes how a member is attributed, small drift
-- there is expected while the money must not move at all.
-- ---------------------------------------------------------------------
WITH actual AS (
    SELECT
        CARE_TYPE                                              AS care_type,
        ROUND(SUM(BILLED_AMOUNT))                              AS billed,
        ROUND(SUM(PAID_BY_PATIENT))                            AS member_paid,
        ROUND(100 * SUM(PAID_BY_PATIENT)
              / NULLIF(SUM(PAID_AMOUNT), 0), 1)                AS member_share,
        COUNT(DISTINCT PATIENT_ID)                             AS people,
        COUNT(DISTINCT PRIMARY_CONDITION)                      AS conditions
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
    WHERE CARE_TYPE <> 'No diagnosis on claim'
    GROUP BY CARE_TYPE
),
-- ---------------------------------------------------------------------
-- !! THE EXPECTED BLOCK BELOW PREDATES THE CHOLECYSTITIS FIX (2026-09-03) !!
--
-- The ladder gained a branch routing "cholecystitis" to Infections (other)
-- before the Kidney & urinary branch could claim it on the substring
-- "cystitis". That moves $14,009,934 and 1,252 patients between exactly two
-- categories:
--
--     Kidney & urinary     6,022,426,729  ->  6,008,416,795   (-0.23%)
--     Infections (other)     324,290,119  ->    338,300,053   (+4.32%)
--
-- Billed is arithmetic and shown above. Member-paid, share and distinct
-- patient counts are NOT, so they are deliberately not guessed here.
--
-- TO REFRESH: re-run sql/analysis/q2_patient_cost_by_care_type.sql, overwrite
-- sql/results/q2_patient_cost_by_care_type_2020_2024.csv, then regenerate this
-- VALUES block from that file. Until then, expect those two rows to FAIL on
-- billed and member paid, and treat every other row as a live check.
-- ---------------------------------------------------------------------
expected AS (
    SELECT * FROM VALUES
        ('Maternity', 29011515724, 4940449888, 17.0, 178766, 5),
        ('Dental & oral', 11827830056, 3295581951, 27.9, 938009, 15),
        ('Allergy & immune', 8659567025, 862954226, 10.0, 49452, 5),
        ('Cancer & tumours', 7099660059, 589210904, 8.3, 67860, 11),
        ('Kidney & urinary', 6022426729, 857098889, 14.2, 167126, 13),
        ('Heart & circulation', 3017010475, 443946673, 14.7, 139952, 13),
        ('Respiratory & ENT', 2498204310, 668382799, 26.8, 937507, 16),
        ('Mental health & substance use', 1561472069, 322408319, 20.6, 200549, 14),
        ('Injury & trauma', 1505374975, 396179724, 26.3, 342757, 28),
        ('Diabetes & metabolic', 434570450, 159224764, 36.6, 259513, 17),
        ('Infections (other)', 324290119, 90874402, 28.0, 13122, 5),
        ('Chronic pain', 275377466, 63000430, 22.9, 31047, 1),
        ('Brain & nervous system', 235913815, 19964000, 8.5, 26392, 3),
        ('Blood disorders', 121478486, 47232822, 38.9, 67419, 1),
        ('Other', 90800915, 16213774, 17.9, 56781, 38)
    AS t(care_type, billed, member_paid, member_share, people, conditions)
)
SELECT
    COALESCE(a.care_type, e.care_type)                         AS "Type of care",
    CASE
        WHEN a.care_type IS NULL THEN 'FAIL - missing from the view'
        WHEN e.care_type IS NULL THEN 'FAIL - not in the published report'
        WHEN a.billed <> e.billed THEN 'FAIL - billed'
        WHEN a.member_paid <> e.member_paid THEN 'FAIL - member paid'
        WHEN ABS(a.member_share - e.member_share) > 0.05 THEN 'FAIL - share'
        WHEN ABS(a.people - e.people) > 0.005 * e.people THEN 'WARN - people affected'
        WHEN a.conditions <> e.conditions THEN 'WARN - condition count'
        ELSE 'PASS'
    END                                                        AS "Result",
    e.billed                                                   AS "Billed, report",
    a.billed                                                   AS "Billed, view",
    a.billed - e.billed                                        AS "Billed drift",
    e.member_paid                                              AS "Member paid, report",
    a.member_paid                                              AS "Member paid, view",
    a.member_paid - e.member_paid                              AS "Member paid drift",
    e.member_share                                             AS "Share, report",
    a.member_share                                             AS "Share, view",
    e.people                                                   AS "People, report",
    a.people                                                   AS "People, view",
    e.conditions                                               AS "Conditions, report",
    a.conditions                                               AS "Conditions, view"
FROM actual a
FULL OUTER JOIN expected e ON a.care_type = e.care_type
ORDER BY COALESCE(e.billed, a.billed) DESC;


-- ---------------------------------------------------------------------
-- PART 3: the bucket PART 1 filtered out, reported rather than hidden.
--
-- This is spend on claims carrying no resolvable clinical diagnosis. It is
-- NOT a care type and it is not in the published report -- the analysis
-- excludes it, which is why the report's denominator is $72.7B against
-- $99.1B billed overall. Expect roughly $26.4B here.
--
-- If a care-type visual in Power BI is meant to reconcile to the report,
-- filter this value out. If the visual is meant to show total cost of care,
-- keep it, and label it so nobody reads it as a clinical category.
-- ---------------------------------------------------------------------
SELECT
    'No diagnosis on claim'                                    AS "Bucket",
    ROUND(SUM(BILLED_AMOUNT))                                  AS "Total bill",
    ROUND(SUM(PAID_BY_PATIENT))                                AS "Paid by members",
    ROUND(100 * SUM(PAID_BY_PATIENT)
          / NULLIF(SUM(PAID_AMOUNT), 0), 1)                    AS "% of the bill members pay",
    COUNT(DISTINCT PATIENT_ID)                                 AS "People affected",
    ROUND(100 * SUM(BILLED_AMOUNT) / (
        SELECT SUM(BILLED_AMOUNT)
        FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE), 1)
                                                               AS "% of all billed"
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
WHERE CARE_TYPE = 'No diagnosis on claim';
