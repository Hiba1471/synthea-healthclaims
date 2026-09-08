-- =====================================================================
-- POWER BI AGGREGATE + DIMENSION TABLES
--
-- Grain follows the filters. Every dimension you want to slice by has to be
-- IN the aggregate, or the slicer cannot move that visual. The dashboard
-- slices by year, care type, payer type and condition, so all four are in
-- AGG_SPEND -- which is why there is one fact table rather than two.
--
-- Six tables:
--   AGG_SPEND       ~2,900 rows   all money and claims
--   AGG_MEMBERS         40 rows   distinct headcounts, long format
--   DIM_CARE_TYPE       16 rows   slicer + drill level 1
--   DIM_CONDITION     ~186 rows   slicer + drill level 2
--   DIM_PAYER_TYPE       3 rows   slicer
--   DIM_YEAR             5 rows   slicer
--
-- NOTE ON THE SOURCE COLUMNS. V_CLAIMS_TX_WITH_CARETYPE has no SERVICEDATE.
-- Its date columns are FROMDATE, SERVICE_YEAR, SERVICE_MONTH,
-- SERVICE_MONTH_START and SERVICE_QUARTER. SERVICE_YEAR is already computed
-- by the view, so it is selected directly rather than wrapped in YEAR().
--
-- TABLE vs VIEW. These are TABLEs -- faster to query, but they go stale when
-- the source changes. Re-run this whole file after any edit to
-- V_CLAIMS_TX_WITH_CARETYPE, especially a care-type ladder change, or Power BI
-- keeps serving the old grouping with no error to warn you.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. AGG_SPEND -- the single fact table.
--
--    Grain: SERVICE_YEAR x CARE_TYPE x PAYER_TYPE x PRIMARY_CONDITION.
--
--    WHY CONDITION IS IN THE GRAIN. With condition in a separate table, a
--    condition slicer leaves the KPI cards, the gauge and the donut
--    untouched -- they read this table and it would not carry condition.
--    Adding it takes the row count from ~240 to ~2,900, which is nothing,
--    and makes every slicer move every visual on the page.
--
--    WHY COALESCE AND NOT A FILTER. Roughly $26.4B of spend sits on claims
--    with no resolvable diagnosis. Dropping those rows would make this table
--    total $72.69B and the headline card would read $72.69bn instead of
--    $99.11bn. They are kept under an explicit label so the total stays whole
--    and the bucket is visible rather than silently missing. Exclude it in a
--    visual when you need to reconcile to the report, whose care-type
--    denominator is the $72.69B of diagnosed spend.
--
--    PAID_TOTAL is stored rather than derived. Member share is member-paid
--    over total PAID, matching q2_who_pays.sql. MEMBER_PAID + PAYER_PAID
--    gives the same answer; storing it means a measure cannot quietly drift
--    to a billed denominator later.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE SYNTHEA_HEALTHCLAIMS.PUBLIC.AGG_SPEND AS
SELECT
    SERVICE_YEAR,
    CARE_TYPE,
    PAYER_TYPE,
    COALESCE(PRIMARY_CONDITION, '(no diagnosis on claim)')      AS PRIMARY_CONDITION,
    SUM(BILLED_AMOUNT)                                          AS BILLED,
    SUM(PAID_BY_PATIENT)                                        AS MEMBER_PAID,
    SUM(PAID_BY_PAYER)                                          AS PAYER_PAID,
    SUM(PAID_AMOUNT)                                            AS PAID_TOTAL,
    COUNT(DISTINCT CLAIM_ID)                                    AS CLAIMS
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
GROUP BY
    SERVICE_YEAR,
    CARE_TYPE,
    PAYER_TYPE,
    COALESCE(PRIMARY_CONDITION, '(no diagnosis on claim)');


-- ---------------------------------------------------------------------
-- 2. AGG_MEMBERS -- distinct counts, long format.
--
--    Separate from AGG_SPEND because distinct counts do not add up. A member
--    appears in several months, care types and possibly both plan types, so
--    summing a member column across rows double-counts them -- the three
--    payer rows for 2020 total 1,166,199 against a true 1,137,017.
--
--    Every grain the dashboard displays therefore has to be stored as its own
--    row, and a measure reads the row it needs. There is deliberately NO
--    condition grain: a headcount per condition would not be meaningful to
--    add up either, and no card on the dashboard shows one.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE SYNTHEA_HEALTHCLAIMS.PUBLIC.AGG_MEMBERS AS
SELECT 'Total' AS GRAIN, 'All members' AS SEGMENT, CAST(NULL AS NUMBER) AS SERVICE_YEAR,
       COUNT(DISTINCT PATIENT_ID) AS MEMBERS
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
UNION ALL
SELECT 'Year', TO_VARCHAR(SERVICE_YEAR), SERVICE_YEAR, COUNT(DISTINCT PATIENT_ID)
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
GROUP BY SERVICE_YEAR
UNION ALL
SELECT 'Payer type', PAYER_TYPE, CAST(NULL AS NUMBER), COUNT(DISTINCT PATIENT_ID)
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
GROUP BY PAYER_TYPE
UNION ALL
SELECT 'Care type', CARE_TYPE, CAST(NULL AS NUMBER), COUNT(DISTINCT PATIENT_ID)
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
GROUP BY CARE_TYPE
UNION ALL
SELECT 'Payer x Year', PAYER_TYPE, SERVICE_YEAR, COUNT(DISTINCT PATIENT_ID)
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
GROUP BY PAYER_TYPE, SERVICE_YEAR;


-- ---------------------------------------------------------------------
-- 3. DIMENSIONS -- slicers go on these, never on AGG_SPEND.
--
--    A Care Type slicer built on AGG_SPEND filters AGG_SPEND only. The same
--    slicer built on DIM_CARE_TYPE filters everything related to it.
--
--    DIM_CONDITION carries CARE_TYPE alongside the condition so the drill
--    hierarchy has both levels available, and so the condition slicer can be
--    cascaded by a care-type selection.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE SYNTHEA_HEALTHCLAIMS.PUBLIC.DIM_CARE_TYPE AS
SELECT DISTINCT
    CARE_TYPE,
    IFF(CARE_TYPE = 'No diagnosis on claim', FALSE, TRUE)       AS IS_CLINICAL
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE;

CREATE OR REPLACE TABLE SYNTHEA_HEALTHCLAIMS.PUBLIC.DIM_CONDITION AS
SELECT DISTINCT
    COALESCE(PRIMARY_CONDITION, '(no diagnosis on claim)')      AS PRIMARY_CONDITION,
    CARE_TYPE,
    IFF(PRIMARY_CONDITION IS NULL, FALSE, TRUE)                 AS IS_CLINICAL
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE;

CREATE OR REPLACE TABLE SYNTHEA_HEALTHCLAIMS.PUBLIC.DIM_PAYER_TYPE AS
SELECT DISTINCT PAYER_TYPE
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE;

CREATE OR REPLACE TABLE SYNTHEA_HEALTHCLAIMS.PUBLIC.DIM_YEAR AS
SELECT DISTINCT SERVICE_YEAR
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE;


-- =====================================================================
-- ACCEPTANCE CHECK.
--
--   AGG_SPEND      billed 99,111,300,188   member paid 20,256,370,607   20.4%
--                  of which 72,685,492,673 carries a diagnosis
--   AGG_MEMBERS    Total row = 1,259,375
--   DIM_CONDITION  every PRIMARY_CONDITION unique -- required for the
--                  one-to-many relationship to AGG_SPEND
--
-- Adding condition to the grain must not change any total. If "Billed" moves,
-- the COALESCE is dropping rows rather than labelling them.
-- =====================================================================
SELECT
    'AGG_SPEND'                                                 AS "Table",
    COUNT(*)                                                    AS "Rows",
    ROUND(SUM(BILLED))                                          AS "Billed",
    ROUND(SUM(MEMBER_PAID))                                     AS "Member paid",
    ROUND(100 * SUM(MEMBER_PAID) / NULLIF(SUM(PAID_TOTAL), 0), 1)
                                                                AS "Share %",
    IFF(ROUND(SUM(BILLED))      = 99111300188
        AND ROUND(SUM(MEMBER_PAID)) = 20256370607, 'PASS', 'CHECK') AS "Result"
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.AGG_SPEND

UNION ALL

SELECT
    'AGG_SPEND, diagnosed only',
    COUNT(*),
    ROUND(SUM(BILLED)),
    ROUND(SUM(MEMBER_PAID)),
    ROUND(100 * SUM(MEMBER_PAID) / NULLIF(SUM(PAID_TOTAL), 0), 1),
    IFF(ROUND(SUM(BILLED)) BETWEEN 72600000000 AND 72800000000, 'PASS', 'CHECK')
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.AGG_SPEND
WHERE PRIMARY_CONDITION <> '(no diagnosis on claim)'

UNION ALL

SELECT
    'AGG_MEMBERS', COUNT(*), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
    IFF(MAX(IFF(GRAIN = 'Total', MEMBERS, NULL)) = 1259375, 'PASS', 'CHECK')
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.AGG_MEMBERS

UNION ALL

SELECT
    'DIM_CONDITION', COUNT(*), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
    IFF(COUNT(*) = COUNT(DISTINCT PRIMARY_CONDITION),
        'PASS - unique key', 'FAIL - duplicate keys break the relationship')
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.DIM_CONDITION;
