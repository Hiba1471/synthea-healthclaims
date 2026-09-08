-- =====================================================================
-- SYNTHEA_HEALTHCLAIMS.PUBLIC.V_SPEND_CONCENTRATION
--
-- One row per grain, answering "how few of these carry half the spend".
-- Built for Power BI to import as a tiny table, because the member grain
-- cannot be computed in DAX at query time -- see the note below.
--
-- Expected output, matching sql/results/q3_concentration_2020_2024.csv:
--
--   GRAIN          HOW MANY EXIST   FOR HALF   % OF THEM   TOP 1%
--   Members             1,259,375    134,198      10.66%     11.8%
--   Facilities              3,918         86       2.20%     32.5%
--
-- WHY THIS IS A VIEW AND NOT A DAX MEASURE. The DAX pattern for "how many
-- entities reach half the spend" ranks the entities and runs a cumulative
-- total, which costs roughly n^2 row comparisons. At the facility grain that
-- is 3,918^2, about 15 million -- slow but survivable. At the member grain it
-- is 1,259,375^2, about 1.6 TRILLION. It does not complete. Snowflake does
-- the same job with a window function in one pass, so it belongs here.
--
-- The consequence is honest rather than hidden: these figures do NOT respond
-- to Power BI slicers. They describe the whole 2020-2024 window. Caption any
-- card bound to them accordingly, or a viewer who filters to 2024 will read
-- the unchanged number as a bug.
--
-- GROUPING KEYS. Members group by PATIENT_ID, facilities by FACILITY_ID
-- (= ENCOUNTERS.ORGANIZATION_ID), matching q3_concentration.sql. Do NOT
-- group facilities by FACILITY_NAME: names are not guaranteed unique, and
-- rows whose organisation did not match collapse into a single blank bucket
-- that ranks near the top. That substitution is what returns 65 instead of 86.
--
-- HAVING SUM(BILLED_AMOUNT) > 0 mirrors the published query, which filtered
-- BILLED_AMOUNT > 0 before grouping. Without it, entities carrying only
-- PAYMENT rows would join the population at zero spend, inflating the
-- denominator and deflating every percentage.
-- =====================================================================

CREATE OR REPLACE VIEW SYNTHEA_HEALTHCLAIMS.PUBLIC.V_SPEND_CONCENTRATION AS
WITH member_totals AS (
    SELECT 'Members' AS grain, PATIENT_ID AS entity, SUM(BILLED_AMOUNT) AS amt
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
    GROUP BY PATIENT_ID
    HAVING SUM(BILLED_AMOUNT) > 0
),
facility_totals AS (
    SELECT 'Facilities' AS grain, TO_VARCHAR(FACILITY_ID) AS entity,
           SUM(BILLED_AMOUNT) AS amt
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
    GROUP BY FACILITY_ID
    HAVING SUM(BILLED_AMOUNT) > 0
),
care_type_totals AS (
    SELECT 'Care types' AS grain, CARE_TYPE AS entity, SUM(BILLED_AMOUNT) AS amt
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
    WHERE CARE_TYPE <> 'No diagnosis on claim'
    GROUP BY CARE_TYPE
    HAVING SUM(BILLED_AMOUNT) > 0
),
all_grains AS (
    SELECT * FROM member_totals
    UNION ALL SELECT * FROM facility_totals
    UNION ALL SELECT * FROM care_type_totals
),
-- one pass per grain: rank, running total, grain total, grain count
ranked AS (
    SELECT
        grain,
        amt,
        ROW_NUMBER() OVER (PARTITION BY grain ORDER BY amt DESC)   AS rk,
        SUM(amt) OVER (PARTITION BY grain ORDER BY amt DESC
              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)    AS running,
        SUM(amt) OVER (PARTITION BY grain)                         AS total,
        COUNT(*)  OVER (PARTITION BY grain)                        AS n
    FROM all_grains
)
SELECT
    grain                                                          AS GRAIN,
    MIN(n)                                                         AS ENTITIES_TOTAL,
    ROUND(MIN(total))                                              AS SPEND_TOTAL,
    MIN(IFF(running >= 0.5 * total, rk, NULL))                     AS ENTITIES_FOR_HALF,
    ROUND(100.0 * MIN(IFF(running >= 0.5 * total, rk, NULL))
          / MIN(n), 2)                                             AS PCT_FOR_HALF,
    MIN(IFF(running >= 0.8 * total, rk, NULL))                     AS ENTITIES_FOR_80PCT,
    ROUND(MAX(IFF(rk = CEIL(0.01 * n), running / total * 100, NULL)), 1) AS TOP_1PCT_SHARE,
    ROUND(MAX(IFF(rk = CEIL(0.05 * n), running / total * 100, NULL)), 1) AS TOP_5PCT_SHARE,
    ROUND(MAX(IFF(rk = CEIL(0.10 * n), running / total * 100, NULL)), 1) AS TOP_10PCT_SHARE
FROM ranked
GROUP BY grain
ORDER BY MIN(n) DESC;


-- =====================================================================
-- ACCEPTANCE CHECK. Run straight after creating the view.
-- Members must return 1,259,375 / 134,198 / 10.66% / 11.8.
-- Facilities must return 3,918 / 86 / 2.20% / 32.5.
--
-- If Members comes back with a different ENTITIES_TOTAL, the HAVING clause
-- or the scope has drifted. If Facilities returns 65, something is grouping
-- by FACILITY_NAME rather than FACILITY_ID.
-- =====================================================================
SELECT
    GRAIN,
    ENTITIES_TOTAL,
    ENTITIES_FOR_HALF,
    PCT_FOR_HALF,
    TOP_1PCT_SHARE,
    CASE
        WHEN GRAIN = 'Members'    AND ENTITIES_FOR_HALF = 134198 THEN 'PASS'
        WHEN GRAIN = 'Facilities' AND ENTITIES_FOR_HALF = 86     THEN 'PASS'
        WHEN GRAIN = 'Care types' AND ENTITIES_FOR_HALF = 2      THEN 'PASS'
        ELSE 'CHECK - does not match the published figure'
    END                                                            AS ACCEPTANCE
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_SPEND_CONCENTRATION
ORDER BY ENTITIES_TOTAL DESC;
