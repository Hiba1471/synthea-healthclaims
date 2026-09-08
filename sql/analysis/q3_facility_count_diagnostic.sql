-- =====================================================================
-- WHY DOES THE POWER BI CARD SAY 65 WHEN THE REPORT SAYS 86?
--
-- Published figure: 86 of 3,918 facilities carry half of all spend (2.20%),
-- from sql/results/q3_concentration_2020_2024.csv, grain 'Organisations'.
--
-- q3_concentration.sql groups by ENCOUNTERS.ORGANIZATION_ID. A DAX measure
-- grouping by FACILITY_NAME instead can differ for two reasons, and these
-- four queries say which one is in play. Run them in order.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. COUNT THE ENTITIES BOTH WAYS.
--
--    facilities_by_id should be 3,918 -- the published denominator.
--    If facilities_by_name is LOWER, some sites share a name and grouping
--    by name merges them into fewer, larger entities. Fewer, larger
--    entities reach half the spend sooner, which lowers the count.
--    If billed_with_no_facility is above zero, the LEFT JOIN to
--    ORGANIZATIONS is not matching every encounter, and those rows collapse
--    into ONE blank bucket that ranks near the top and absorbs spend.
-- ---------------------------------------------------------------------
SELECT
    COUNT(DISTINCT FACILITY_ID)                                AS "Facilities by id",
    COUNT(DISTINCT FACILITY_NAME)                              AS "Facilities by name",
    COUNT(DISTINCT FACILITY_ID) - COUNT(DISTINCT FACILITY_NAME)
                                                               AS "Names lost to collision",
    SUM(IFF(FACILITY_NAME IS NULL, BILLED_AMOUNT, 0))          AS "Billed with no facility name",
    ROUND(100 * SUM(IFF(FACILITY_NAME IS NULL, BILLED_AMOUNT, 0))
          / NULLIF(SUM(BILLED_AMOUNT), 0), 2)                  AS "% of billed unmatched"
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE;


-- ---------------------------------------------------------------------
-- 2. REPRODUCE THE PUBLISHED 86 FROM THE VIEW, grouping by id.
--    This is the same method q3_concentration.sql uses, so it should
--    return 86. If it does, the view is fine and only the DAX needs fixing.
-- ---------------------------------------------------------------------
WITH fac AS (
    SELECT FACILITY_ID, SUM(BILLED_AMOUNT) AS amt
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
    GROUP BY FACILITY_ID
),
ranked AS (
    SELECT
        amt,
        ROW_NUMBER() OVER (ORDER BY amt DESC)                  AS rk,
        SUM(amt) OVER (ORDER BY amt DESC
              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running,
        SUM(amt) OVER ()                                       AS total,
        COUNT(*) OVER ()                                       AS n
    FROM fac
)
SELECT
    'Grouped by FACILITY_ID'                                   AS "Method",
    MIN(n)                                                     AS "Facilities in total",
    MIN(IFF(running >= 0.5 * total, rk, NULL))                 AS "Needed for half of spend",
    ROUND(100 * MIN(IFF(running >= 0.5 * total, rk, NULL))
          / MIN(n), 2)                                         AS "% of the network"
FROM ranked;


-- ---------------------------------------------------------------------
-- 3. THE SAME THING GROUPED BY NAME, for comparison. If this returns 65,
--    the difference is entirely the grouping key and query 1 says why.
-- ---------------------------------------------------------------------
WITH fac AS (
    SELECT FACILITY_NAME, SUM(BILLED_AMOUNT) AS amt
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
    GROUP BY FACILITY_NAME
),
ranked AS (
    SELECT
        amt,
        ROW_NUMBER() OVER (ORDER BY amt DESC)                  AS rk,
        SUM(amt) OVER (ORDER BY amt DESC
              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running,
        SUM(amt) OVER ()                                       AS total,
        COUNT(*) OVER ()                                       AS n
    FROM fac
)
SELECT
    'Grouped by FACILITY_NAME'                                 AS "Method",
    MIN(n)                                                     AS "Facilities in total",
    MIN(IFF(running >= 0.5 * total, rk, NULL))                 AS "Needed for half of spend",
    ROUND(100 * MIN(IFF(running >= 0.5 * total, rk, NULL))
          / MIN(n), 2)                                         AS "% of the network"
FROM ranked;


-- ---------------------------------------------------------------------
-- 4. IF QUERY 1 SHOWED NAME COLLISIONS, this names them: one row per
--    facility name carried by more than one ORGANIZATION_ID.
-- ---------------------------------------------------------------------
SELECT
    FACILITY_NAME                                              AS "Facility name",
    COUNT(DISTINCT FACILITY_ID)                                AS "Distinct sites sharing it",
    ROUND(SUM(BILLED_AMOUNT))                                  AS "Billed across them"
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
WHERE FACILITY_NAME IS NOT NULL
GROUP BY FACILITY_NAME
HAVING COUNT(DISTINCT FACILITY_ID) > 1
ORDER BY SUM(BILLED_AMOUNT) DESC;
