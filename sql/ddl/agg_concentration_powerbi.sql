-- =====================================================================
-- CONCENTRATION PAGE -- three more tables for Power BI
--
-- The six tables in agg_tables_powerbi.sql cover the Overview, Care Type and
-- Plan Type pages. None of them carries a facility or a per-member
-- distribution, so the Concentration page needs these:
--
--   AGG_FACILITY       3,918 rows  one per facility, rank and cumulative %
--   AGG_CONCENTRATION      3 rows  the headline thresholds per grain
--   AGG_LORENZ          ~200 rows  the two curves, members and facilities
--
-- Import all three. AGG_FACILITY relates to nothing (it is its own grain);
-- the other two are lookup tables read by measures, like AGG_MEMBERS.
--
-- ---------------------------------------------------------------------
-- PREREQUISITE: FACILITY_ID must exist on V_CLAIMS_TX_WITH_CARETYPE.
--
-- If you have not re-created that view since FACILITY_ID was added, these
-- will fail on an unknown column. Re-create it first.
--
-- Grouping by FACILITY_NAME instead is what returns 65 facilities for half of
-- spend rather than 86: names are not guaranteed unique across sites, and
-- rows whose organisation did not match the join collapse into one blank
-- bucket that ranks near the top.
--
-- ---------------------------------------------------------------------
-- WHY THE RANK AND CUMULATIVE % ARE PRECOMPUTED.
--
-- "How many entities reach half the spend" needs a ranked running total. In
-- DAX that costs roughly n^2 row comparisons -- survivable at 3,918
-- facilities, impossible at 1,259,375 members (about 1.6 trillion). Snowflake
-- does it with a window function in one pass, so it is done here and Power BI
-- just reads a column.
--
-- The consequence is honest rather than hidden: these figures describe the
-- whole 2020-2024 window and do NOT respond to slicers. Caption the cards
-- "2020-2024, all payers" so an unchanged number reads as intentional.
--
-- HAVING SUM(BILLED_AMOUNT) > 0 mirrors q3_concentration.sql, which filtered
-- BILLED_AMOUNT > 0 before grouping. Without it, entities carrying only
-- PAYMENT rows join the population at zero spend, inflating the denominator
-- and deflating every percentage.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. AGG_FACILITY -- one row per facility, whole window.
--
--    VISITS_PER_MEMBER is the column that makes this page say something.
--    Billed alone ranks facilities by size; visits per member says WHY one
--    is expensive -- many people coming a few times, or few people coming
--    constantly. Ordinary hospitals sit near 20, the dialysis sites near 50.
-- ---------------------------------------------------------------------
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


-- ---------------------------------------------------------------------
-- 2. AGG_CONCENTRATION -- the headline thresholds, one row per grain.
--
--    Expected, matching sql/results/q3_concentration_2020_2024.csv:
--      Members     1,259,375 exist,   134,198 for half (10.66%), top 1% = 11.8%
--      Facilities      3,918 exist,        86 for half  (2.20%), top 1% = 32.5%
--      Care types         16 exist,         2 for half
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE SYNTHEA_HEALTHCLAIMS.PUBLIC.AGG_CONCENTRATION AS
WITH entities AS (
    SELECT 'Members' AS grain, TO_VARCHAR(PATIENT_ID) AS entity, SUM(BILLED_AMOUNT) AS amt
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
    GROUP BY PATIENT_ID HAVING SUM(BILLED_AMOUNT) > 0
    UNION ALL
    SELECT 'Facilities', TO_VARCHAR(FACILITY_ID), SUM(BILLED_AMOUNT)
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
    GROUP BY FACILITY_ID HAVING SUM(BILLED_AMOUNT) > 0
    UNION ALL
    SELECT 'Care types', CARE_TYPE, SUM(BILLED_AMOUNT)
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
    GROUP BY CARE_TYPE HAVING SUM(BILLED_AMOUNT) > 0
),
ranked AS (
    SELECT
        grain, amt,
        ROW_NUMBER() OVER (PARTITION BY grain ORDER BY amt DESC)  AS rk,
        SUM(amt) OVER (PARTITION BY grain ORDER BY amt DESC
              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)   AS running,
        SUM(amt) OVER (PARTITION BY grain)                        AS total,
        COUNT(*)  OVER (PARTITION BY grain)                       AS n
    FROM entities
)
SELECT
    grain                                                        AS GRAIN,
    MIN(n)                                                       AS ENTITIES_TOTAL,
    ROUND(MIN(total))                                            AS SPEND_TOTAL,
    MIN(IFF(running >= 0.5 * total, rk, NULL))                   AS ENTITIES_FOR_HALF,
    ROUND(100.0 * MIN(IFF(running >= 0.5 * total, rk, NULL)) / MIN(n), 2)
                                                                 AS PCT_FOR_HALF,
    MIN(IFF(running >= 0.8 * total, rk, NULL))                   AS ENTITIES_FOR_80PCT,
    ROUND(MAX(IFF(rk = CEIL(0.01 * n), running / total * 100, NULL)), 1) AS TOP_1PCT_SHARE,
    ROUND(MAX(IFF(rk = CEIL(0.05 * n), running / total * 100, NULL)), 1) AS TOP_5PCT_SHARE,
    ROUND(MAX(IFF(rk = CEIL(0.10 * n), running / total * 100, NULL)), 1) AS TOP_10PCT_SHARE
FROM ranked
GROUP BY grain;


-- ---------------------------------------------------------------------
-- 3. AGG_LORENZ -- the curves. 100 points per grain.
--
--    PCT_OF_GROUP 1..100 against PCT_OF_SPEND. Plot as a line with
--    PCT_OF_GROUP on the x-axis and a 45-degree reference line for
--    "perfectly even". The further a curve bows above the diagonal, the more
--    concentrated that grain is.
--
--    Facilities bow sharply (top 1% carry 32.5%); members barely do (11.8%).
--    That contrast IS the finding, and it needs both curves on one chart.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE SYNTHEA_HEALTHCLAIMS.PUBLIC.AGG_LORENZ AS
WITH entities AS (
    SELECT 'Members' AS grain, TO_VARCHAR(PATIENT_ID) AS entity, SUM(BILLED_AMOUNT) AS amt
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
    GROUP BY PATIENT_ID HAVING SUM(BILLED_AMOUNT) > 0
    UNION ALL
    SELECT 'Facilities', TO_VARCHAR(FACILITY_ID), SUM(BILLED_AMOUNT)
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
    GROUP BY FACILITY_ID HAVING SUM(BILLED_AMOUNT) > 0
),
ranked AS (
    SELECT
        grain,
        ROW_NUMBER() OVER (PARTITION BY grain ORDER BY amt DESC)  AS rk,
        SUM(amt) OVER (PARTITION BY grain ORDER BY amt DESC
              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)   AS running,
        SUM(amt) OVER (PARTITION BY grain)                        AS total,
        COUNT(*)  OVER (PARTITION BY grain)                       AS n
    FROM entities
)
SELECT
    grain                                                        AS GRAIN,
    CEIL(100.0 * rk / n)                                         AS PCT_OF_GROUP,
    ROUND(MAX(100.0 * running / total), 2)                       AS PCT_OF_SPEND
FROM ranked
GROUP BY grain, CEIL(100.0 * rk / n);


-- =====================================================================
-- ACCEPTANCE CHECK.
--   AGG_FACILITY       3,918 rows, billed 99,111,300,188, 86 for half
--   AGG_CONCENTRATION  Facilities 86 / Members 134,198 / Care types 2
--   AGG_LORENZ         200 rows, and the 1% point = 32.5 / 11.8
-- =====================================================================
SELECT 'AGG_FACILITY'                                            AS "Table",
       COUNT(*)                                                  AS "Rows",
       ROUND(SUM(BILLED))                                        AS "Billed",
       MIN(IFF(CUMULATIVE_PCT >= 50, SPEND_RANK, NULL))          AS "For half",
       IFF(COUNT(*) = 3918
           AND ROUND(SUM(BILLED)) = 99111300188
           AND MIN(IFF(CUMULATIVE_PCT >= 50, SPEND_RANK, NULL)) = 86,
           'PASS', 'CHECK - see the FACILITY_ID note')           AS "Result"
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.AGG_FACILITY
UNION ALL
SELECT 'AGG_CONCENTRATION', COUNT(*), CAST(NULL AS NUMBER),
       MAX(IFF(GRAIN = 'Facilities', ENTITIES_FOR_HALF, NULL)),
       IFF(MAX(IFF(GRAIN = 'Facilities', ENTITIES_FOR_HALF, NULL)) = 86
           AND MAX(IFF(GRAIN = 'Members', ENTITIES_FOR_HALF, NULL)) = 134198,
           'PASS', 'CHECK')
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.AGG_CONCENTRATION
UNION ALL
SELECT 'AGG_LORENZ', COUNT(*), CAST(NULL AS NUMBER),
       CAST(NULL AS NUMBER),
       IFF(MAX(IFF(GRAIN = 'Facilities' AND PCT_OF_GROUP = 1, PCT_OF_SPEND, NULL)) BETWEEN 32 AND 33
           AND MAX(IFF(GRAIN = 'Members' AND PCT_OF_GROUP = 1, PCT_OF_SPEND, NULL)) BETWEEN 11 AND 12,
           'PASS', 'CHECK')
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.AGG_LORENZ;
