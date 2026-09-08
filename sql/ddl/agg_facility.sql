-- =====================================================================
-- AGG_FACILITY -- one row per facility, whole 2020-2024 window.
--
-- Needed for the Facility & Geography page: the rank-vs-billed long-tail
-- scatter, the price-vs-frequency scatter (BILLED_PER_VISIT vs
-- VISITS_PER_MEMBER), and the top-facilities bar chart.
--
-- VISITS_PER_MEMBER is the column that makes those charts say something
-- beyond "this facility is big." Billed alone ranks facilities by size;
-- visits per member says WHY one is expensive -- many people coming a few
-- times, or few people coming constantly. Ordinary hospitals sit near 20
-- visits per member; the dialysis-heavy sites sit near 50.
--
-- ---------------------------------------------------------------------
-- PREREQUISITE: FACILITY_ID must exist on V_CLAIMS_TX_WITH_CARETYPE.
--
-- If that view has not been re-created since FACILITY_ID was added to it,
-- this fails with "invalid identifier 'FACILITY_ID'". Re-run
-- v_claims_tx_with_caretype.sql first, then this file.
--
-- Grouping by FACILITY_NAME instead is what returns 65 facilities for half
-- of spend rather than the published 86: names are not guaranteed unique
-- across sites, and rows whose organisation did not match the join collapse
-- into one blank bucket that ranks near the top and distorts the count.
--
-- ---------------------------------------------------------------------
-- WHY SPEND_RANK AND CUMULATIVE_PCT ARE PRECOMPUTED HERE, NOT IN DAX.
--
-- Ranking 3,918 facilities and running a cumulative total costs roughly
-- n^2 row comparisons in DAX -- slow, and the same pattern does not
-- complete at all on 1.26M members. Snowflake does the identical job with
-- a window function in one pass, so it is done once here and Power BI
-- just reads a column instead of recomputing it live.
--
-- This table describes the WHOLE window and does not respond to Year or
-- Payer Type slicers -- it is not related to anything else in the model.
-- Caption any card built from it "2020-2024, all payers" so a number that
-- never moves under a filter reads as intentional, not broken.
--
-- HAVING SUM(BILLED_AMOUNT) > 0 mirrors q3_concentration.sql, which
-- filtered BILLED_AMOUNT > 0 before grouping. Without it, a facility whose
-- only rows are PAYMENT lines (BILLED_AMOUNT = 0 on those rows) joins the
-- population at zero spend, inflating the facility count and deflating
-- every percentage computed from it.
-- =====================================================================

CREATE OR REPLACE TABLE SYNTHEA_HEALTHCLAIMS.PUBLIC.AGG_FACILITY AS
SELECT
    FACILITY_ID,
    MAX(COALESCE(FACILITY_NAME, '(no facility on record)'))     AS FACILITY_NAME,
    MAX(FACILITY_CITY)                                          AS FACILITY_CITY,
    MAX(FACILITY_STATE)                                         AS FACILITY_STATE,
    MAX(COALESCE(FACILITY_NAME, '(no facility on record)')
        || ' | ' || COALESCE(FACILITY_CITY, '')
        || ', '  || COALESCE(FACILITY_STATE, ''))               AS FACILITY_LABEL,
    SUM(BILLED_AMOUNT)                                          AS BILLED,
    SUM(PAID_BY_PATIENT)                                        AS MEMBER_PAID,
    COUNT(DISTINCT CLAIM_ID)                                    AS CLAIMS,
    COUNT(DISTINCT ENCOUNTER_ID)                                AS ENCOUNTERS,
    COUNT(DISTINCT PATIENT_ID)                                  AS MEMBERS,
    ROUND(COUNT(DISTINCT ENCOUNTER_ID)
          / NULLIF(COUNT(DISTINCT PATIENT_ID), 0), 2)           AS VISITS_PER_MEMBER,
    ROUND(SUM(BILLED_AMOUNT)
          / NULLIF(COUNT(DISTINCT PATIENT_ID), 0), 2)           AS BILLED_PER_MEMBER,
    ROUND(SUM(BILLED_AMOUNT)
          / NULLIF(COUNT(DISTINCT ENCOUNTER_ID), 0), 2)         AS BILLED_PER_VISIT,
    ROW_NUMBER() OVER (ORDER BY SUM(BILLED_AMOUNT) DESC)        AS SPEND_RANK,
    ROUND(100 * SUM(SUM(BILLED_AMOUNT)) OVER (ORDER BY SUM(BILLED_AMOUNT) DESC
              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
          / SUM(SUM(BILLED_AMOUNT)) OVER (), 4)                 AS CUMULATIVE_PCT
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
GROUP BY FACILITY_ID
HAVING SUM(BILLED_AMOUNT) > 0;


-- =====================================================================
-- ACCEPTANCE CHECK.
--   Rows              3,918
--   Billed            99,111,300,188
--   Facilities for half of spend   86
--
-- If ROWS is not 3,918, or FOR_HALF is not 86, the grouping key is wrong --
-- almost always because FACILITY_ID does not exist yet on the base view
-- (see the prerequisite note above) and something silently grouped by name
-- instead.
-- =====================================================================
SELECT
    COUNT(*)                                                    AS "Rows",
    ROUND(SUM(BILLED))                                          AS "Billed",
    MIN(IFF(CUMULATIVE_PCT >= 50, SPEND_RANK, NULL))            AS "Facilities for half of spend",
    IFF(COUNT(*) = 3918
        AND ROUND(SUM(BILLED)) = 99111300188
        AND MIN(IFF(CUMULATIVE_PCT >= 50, SPEND_RANK, NULL)) = 86,
        'PASS', 'CHECK - see the FACILITY_ID prerequisite note')  AS "Result"
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.AGG_FACILITY;
