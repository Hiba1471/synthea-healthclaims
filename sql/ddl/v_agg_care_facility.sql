-- =====================================================================
-- CARE TYPE AND FACILITY AGGREGATES FOR POWER BI
--
--   V_AGG_CARE_TYPE       ~16 rows    -- care-type page, overview bars
--   V_AGG_FACILITY_TOTAL  3,918 rows  -- concentration page, facility visuals
--
-- WHY THESE EXIST WHEN THE OTHER AGGREGATES ROLL UP.
--
-- Only one reason, and it is the same reason every time: money is additive
-- and distinct counts are not. SUM(BILLED) is correct at any grain, so a
-- finer table always serves a coarser cut. COUNT(DISTINCT PATIENT_ID) is
-- correct only at the grain it was computed on -- a member spans months,
-- years, care types and facilities, so re-summing double-counts them.
--
-- V_AGG_SPEND already gives care-type MONEY by roll-up. What it cannot give
-- is care-type MEMBERS, because its grain is month x payer x care type and a
-- member appears in many of those rows. Same for V_AGG_FACILITY, whose grain
-- includes the year: summing its member column across five years counts
-- anyone who came back more than once.
--
-- If a visual only needs money, it does not need these views.
--
-- ---------------------------------------------------------------------
-- PREREQUISITE FOR V_AGG_FACILITY_TOTAL: FACILITY_ID.
--
-- It groups by FACILITY_ID (= ENCOUNTERS.ORGANIZATION_ID), which is what
-- q3_concentration.sql uses to arrive at "86 of 3,918 facilities carry half
-- of spend". If V_CLAIMS_TX_WITH_CARETYPE has not been re-created since
-- FACILITY_ID was added to it, this view will fail on an unknown column --
-- re-create that view first.
--
-- Grouping by FACILITY_NAME instead is what returns 65 rather than 86: names
-- are not guaranteed unique across sites, and rows whose organisation did not
-- match the join collapse into one blank bucket that ranks near the top.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. V_AGG_CARE_TYPE -- one row per care type, whole window.
--
--    Includes the 'No diagnosis on claim' bucket so the view totals to
--    $99.11B. Filter it out in Power BI for anything that must reconcile
--    to the report, whose denominator is the $72.69B of diagnosed spend.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW SYNTHEA_HEALTHCLAIMS.PUBLIC.V_AGG_CARE_TYPE AS
SELECT
    CARE_TYPE,
    IFF(CARE_TYPE = 'No diagnosis on claim', FALSE, TRUE)       AS IS_CLINICAL,
    COUNT(DISTINCT PRIMARY_CONDITION)                           AS CONDITIONS,
    SUM(BILLED_AMOUNT)                                          AS BILLED,
    SUM(PAID_AMOUNT)                                            AS PAID_TOTAL,
    SUM(PAID_BY_PAYER)                                          AS PAID_BY_INSURER,
    SUM(PAID_BY_PATIENT)                                        AS PAID_BY_MEMBERS,
    ROUND(100 * SUM(PAID_BY_PATIENT)
          / NULLIF(SUM(PAID_AMOUNT), 0), 1)                     AS MEMBER_PAID_SHARE_PCT,
    COUNT(DISTINCT CLAIM_ID)                                    AS CLAIMS,
    COUNT(DISTINCT PATIENT_ID)                                  AS MEMBERS,
    ROUND(SUM(BILLED_AMOUNT)
          / NULLIF(COUNT(DISTINCT PATIENT_ID), 0), 2)           AS BILLED_PER_MEMBER,
    ROUND(SUM(PAID_BY_PATIENT)
          / NULLIF(COUNT(DISTINCT PATIENT_ID), 0), 2)           AS MEMBER_PAID_PER_MEMBER,
    ROUND(SUM(BILLED_AMOUNT)
          / NULLIF(COUNT(DISTINCT CLAIM_ID), 0), 2)             AS AVG_COST_PER_CLAIM,
    ROUND(COUNT(DISTINCT CLAIM_ID)
          / NULLIF(COUNT(DISTINCT PATIENT_ID), 0), 2)           AS AVG_CLAIMS_PER_MEMBER,
    -- the split by line of business, which the blended share hides
    ROUND(100 * SUM(IFF(PAYER_TYPE = 'Commercial', PAID_BY_PATIENT, 0))
          / NULLIF(SUM(IFF(PAYER_TYPE = 'Commercial', PAID_AMOUNT, 0)), 0), 1)
                                                                AS SHARE_COMMERCIAL_PCT,
    ROUND(100 * SUM(IFF(PAYER_TYPE = 'Government', PAID_BY_PATIENT, 0))
          / NULLIF(SUM(IFF(PAYER_TYPE = 'Government', PAID_AMOUNT, 0)), 0), 1)
                                                                AS SHARE_GOVERNMENT_PCT
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
GROUP BY CARE_TYPE;


-- ---------------------------------------------------------------------
-- 2. V_AGG_FACILITY_TOTAL -- one row per facility, whole window.
--
--    VISITS_PER_MEMBER is the column that earns this view. Billed alone
--    ranks facilities by size; visits per member says WHY one is expensive
--    -- many people coming a few times, or few people coming constantly.
--    The dialysis sites sit near 50, the ordinary hospitals near 20.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW SYNTHEA_HEALTHCLAIMS.PUBLIC.V_AGG_FACILITY_TOTAL AS
SELECT
    FACILITY_ID,
    MAX(FACILITY_NAME)                                          AS FACILITY_NAME,
    MAX(FACILITY_CITY)                                          AS FACILITY_CITY,
    MAX(FACILITY_STATE)                                         AS FACILITY_STATE,
    MAX(COALESCE(FACILITY_NAME, '(no facility on record)')
        || ' | ' || COALESCE(FACILITY_CITY, '')
        || ', '  || COALESCE(FACILITY_STATE, ''))               AS FACILITY_LABEL,
    SUM(BILLED_AMOUNT)                                          AS BILLED,
    SUM(PAID_BY_PATIENT)                                        AS PAID_BY_MEMBERS,
    COUNT(DISTINCT CLAIM_ID)                                    AS CLAIMS,
    COUNT(DISTINCT ENCOUNTER_ID)                                AS ENCOUNTERS,
    COUNT(DISTINCT PATIENT_ID)                                  AS MEMBERS,
    ROUND(COUNT(DISTINCT ENCOUNTER_ID)
          / NULLIF(COUNT(DISTINCT PATIENT_ID), 0), 2)           AS VISITS_PER_MEMBER,
    ROUND(SUM(BILLED_AMOUNT)
          / NULLIF(COUNT(DISTINCT PATIENT_ID), 0), 2)           AS BILLED_PER_MEMBER,
    ROUND(SUM(BILLED_AMOUNT)
          / NULLIF(COUNT(DISTINCT ENCOUNTER_ID), 0), 2)         AS BILLED_PER_VISIT,
    -- rank and cumulative share, precomputed so Power BI never has to do the
    -- n^2 running-total pattern that makes the concentration measure slow
    ROW_NUMBER() OVER (ORDER BY SUM(BILLED_AMOUNT) DESC)        AS SPEND_RANK,
    ROUND(100 * SUM(SUM(BILLED_AMOUNT)) OVER (ORDER BY SUM(BILLED_AMOUNT) DESC
              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
          / SUM(SUM(BILLED_AMOUNT)) OVER (), 4)                 AS CUMULATIVE_PCT
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
GROUP BY FACILITY_ID;


-- =====================================================================
-- ACCEPTANCE CHECK.
--
--   V_AGG_CARE_TYPE       16 rows, billed 99,111,300,188 in total,
--                         72,685,492,673 excluding 'No diagnosis on claim'
--   V_AGG_FACILITY_TOTAL  3,918 rows, billed 99,111,300,188,
--                         86 facilities to reach 50% of spend
--
-- If the facility count is not 3,918, the view is not grouping by
-- FACILITY_ID -- check that V_CLAIMS_TX_WITH_CARETYPE has been re-created
-- with that column.
-- =====================================================================
SELECT
    'V_AGG_CARE_TYPE'                                           AS "View",
    COUNT(*)                                                    AS "Rows",
    ROUND(SUM(BILLED))                                          AS "Billed, all",
    ROUND(SUM(IFF(IS_CLINICAL, BILLED, 0)))                     AS "Billed, diagnosed only",
    IFF(ROUND(SUM(BILLED)) = 99111300188
        AND ROUND(SUM(IFF(IS_CLINICAL, BILLED, 0))) BETWEEN 72600000000 AND 72800000000,
        'PASS', 'CHECK')                                        AS "Result"
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_AGG_CARE_TYPE
UNION ALL
SELECT
    'V_AGG_FACILITY_TOTAL',
    COUNT(*),
    ROUND(SUM(BILLED)),
    MIN(IFF(CUMULATIVE_PCT >= 50, SPEND_RANK, NULL)),           -- facilities for half
    IFF(COUNT(*) = 3918
        AND ROUND(SUM(BILLED)) = 99111300188
        AND MIN(IFF(CUMULATIVE_PCT >= 50, SPEND_RANK, NULL)) = 86,
        'PASS', 'CHECK - see the FACILITY_ID note in the header')
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_AGG_FACILITY_TOTAL;
