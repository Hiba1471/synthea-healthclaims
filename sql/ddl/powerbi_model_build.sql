-- =====================================================================
-- POWER BI MODEL BUILD -- every aggregate table behind the dashboard.
--
-- Run top to bottom. Creates 10 tables: 6 for the core question pages,
-- 4 for the supplementary Facility & Geography page.
--
-- PREREQUISITE: V_CLAIMS_TX_WITH_CARETYPE must exist and include
-- FACILITY_ID. See sql/ddl/v_claims_tx_with_caretype.sql.
--
-- Re-run this whole file after ANY change to that view -- these are TABLEs,
-- so they go stale silently and Power BI keeps serving the old numbers.
--
-- Acceptance totals: billed 99,111,300,188 | member paid 20,256,370,607
--                    diagnosed spend 72,685,492,673 | members 1,259,375
-- =====================================================================


-- =====================================================================
-- PART 1 -- CORE MODEL (Overview + Cost Concentration pages)
-- =====================================================================

-- The single fact table. Grain includes condition so a condition slicer
-- moves every visual; without it the KPIs and donut would sit still.
-- COALESCE keeps the ~$26.4B of undiagnosed spend visible under a label
-- instead of dropping it and making the headline read $72.69bn.
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
GROUP BY SERVICE_YEAR, CARE_TYPE, PAYER_TYPE,
         COALESCE(PRIMARY_CONDITION, '(no diagnosis on claim)');


-- Distinct member counts, stored per grain in long format.
-- Separate table because distinct counts do NOT sum -- a member appears in
-- several care types and possibly both plan types. The Member Count measure
-- reads whichever row matches the current selection.
CREATE OR REPLACE TABLE SYNTHEA_HEALTHCLAIMS.PUBLIC.AGG_MEMBERS AS
SELECT 'Total' AS GRAIN, 'All members' AS SEGMENT, CAST(NULL AS NUMBER) AS SERVICE_YEAR,
       COUNT(DISTINCT PATIENT_ID) AS MEMBERS
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
UNION ALL
SELECT 'Year', TO_VARCHAR(SERVICE_YEAR), SERVICE_YEAR, COUNT(DISTINCT PATIENT_ID)
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE GROUP BY SERVICE_YEAR
UNION ALL
SELECT 'Payer type', PAYER_TYPE, CAST(NULL AS NUMBER), COUNT(DISTINCT PATIENT_ID)
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE GROUP BY PAYER_TYPE
UNION ALL
SELECT 'Care type', CARE_TYPE, CAST(NULL AS NUMBER), COUNT(DISTINCT PATIENT_ID)
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE GROUP BY CARE_TYPE
UNION ALL
SELECT 'Payer x Year', PAYER_TYPE, SERVICE_YEAR, COUNT(DISTINCT PATIENT_ID)
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE GROUP BY PAYER_TYPE, SERVICE_YEAR;


-- Care type dimension. Slicers go here, never on AGG_SPEND -- a slicer built
-- on the fact table filters only that table. IS_CLINICAL flags the
-- "No diagnosis on claim" bucket so care-type visuals can exclude it.
CREATE OR REPLACE TABLE SYNTHEA_HEALTHCLAIMS.PUBLIC.DIM_CARE_TYPE AS
SELECT DISTINCT
    CARE_TYPE,
    IFF(CARE_TYPE = 'No diagnosis on claim', FALSE, TRUE)       AS IS_CLINICAL
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE;


-- Condition dimension -- drill level below care type, and the condition slicer.
-- Carries CARE_TYPE so the drill hierarchy has both levels available.
CREATE OR REPLACE TABLE SYNTHEA_HEALTHCLAIMS.PUBLIC.DIM_CONDITION AS
SELECT DISTINCT
    COALESCE(PRIMARY_CONDITION, '(no diagnosis on claim)')      AS PRIMARY_CONDITION,
    CARE_TYPE,
    IFF(PRIMARY_CONDITION IS NULL, FALSE, TRUE)                 AS IS_CLINICAL
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE;


-- Payer type dimension -- 3 rows, drives the payer slicer and the donut.
CREATE OR REPLACE TABLE SYNTHEA_HEALTHCLAIMS.PUBLIC.DIM_PAYER_TYPE AS
SELECT DISTINCT PAYER_TYPE
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE;


-- Year dimension -- 5 rows, drives the year slicer and the trend chart axis.
CREATE OR REPLACE TABLE SYNTHEA_HEALTHCLAIMS.PUBLIC.DIM_YEAR AS
SELECT DISTINCT SERVICE_YEAR
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE;


-- =====================================================================
-- PART 2 -- FACILITY & GEOGRAPHY (supplementary page)
--
-- These four relate to NOTHING in the model. They are whole-window
-- aggregates read directly by their own visuals, so they do not respond to
-- the Year/Payer slicers. That is deliberate -- rank and cumulative % are
-- precomputed here because doing them in DAX is O(n^2), which is slow at
-- 3,918 facilities and does not complete at 1.26M members.
-- =====================================================================

-- One row per facility. BILLED_PER_VISIT and VISITS_PER_MEMBER drive the
-- price-vs-frequency scatter; SPEND_RANK and CUMULATIVE_PCT feed the
-- concentration KPIs. HAVING > 0 drops facilities with only payment rows.
CREATE OR REPLACE TABLE SYNTHEA_HEALTHCLAIMS.PUBLIC.AGG_FACILITY AS
SELECT
    FACILITY_ID,
    MAX(COALESCE(FACILITY_NAME, '(no facility on record)'))     AS FACILITY_NAME,
    MAX(FACILITY_CITY)                                          AS FACILITY_CITY,
    MAX(FACILITY_STATE)                                         AS FACILITY_STATE,
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


-- One row per state. Feeds the choropleth map and the states-for-half KPI.
-- PATIENT_STATE is where the member lives -- not the same as FACILITY_STATE.
CREATE OR REPLACE TABLE SYNTHEA_HEALTHCLAIMS.PUBLIC.AGG_STATE AS
SELECT
    COALESCE(PATIENT_STATE, '(no state on record)')             AS PATIENT_STATE,
    SUM(BILLED_AMOUNT)                                          AS BILLED,
    SUM(PAID_BY_PATIENT)                                        AS MEMBER_PAID,
    COUNT(DISTINCT CLAIM_ID)                                    AS CLAIMS,
    COUNT(DISTINCT PATIENT_ID)                                  AS MEMBERS,
    ROUND(SUM(BILLED_AMOUNT)
          / NULLIF(COUNT(DISTINCT PATIENT_ID), 0), 2)           AS BILLED_PER_MEMBER,
    ROW_NUMBER() OVER (ORDER BY SUM(BILLED_AMOUNT) DESC)        AS SPEND_RANK,
    ROUND(100 * SUM(SUM(BILLED_AMOUNT)) OVER (ORDER BY SUM(BILLED_AMOUNT) DESC
              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
          / SUM(SUM(BILLED_AMOUNT)) OVER (), 4)                 AS CUMULATIVE_PCT
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
GROUP BY COALESCE(PATIENT_STATE, '(no state on record)');


-- Headline concentration thresholds, one row per grain. Feeds the
-- "86 facilities carry half of spend" and "top 1% carry 32.9%" KPI cards.
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
    SELECT grain, amt,
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


-- The two concentration curves, 100 percentile buckets each. Plotted as
-- % of group (x) against % of spend (y) -- facilities bow sharply, members
-- much less, and that gap between the curves is the finding.
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
    SELECT grain,
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
-- ACCEPTANCE CHECK -- run after the build. All rows should read PASS.
-- =====================================================================
SELECT 'AGG_SPEND' AS "Table", COUNT(*) AS "Rows",
       ROUND(SUM(BILLED)) AS "Billed",
       IFF(ROUND(SUM(BILLED)) = 99111300188
           AND ROUND(SUM(MEMBER_PAID)) = 20256370607, 'PASS', 'CHECK') AS "Result"
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.AGG_SPEND
UNION ALL
SELECT 'AGG_SPEND (diagnosed)', COUNT(*), ROUND(SUM(BILLED)),
       IFF(ROUND(SUM(BILLED)) BETWEEN 72600000000 AND 72800000000, 'PASS', 'CHECK')
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.AGG_SPEND
WHERE PRIMARY_CONDITION <> '(no diagnosis on claim)'
UNION ALL
SELECT 'AGG_MEMBERS', COUNT(*), CAST(NULL AS NUMBER),
       IFF(MAX(IFF(GRAIN = 'Total', MEMBERS, NULL)) = 1259375, 'PASS', 'CHECK')
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.AGG_MEMBERS
UNION ALL
SELECT 'DIM_CONDITION', COUNT(*), CAST(NULL AS NUMBER),
       IFF(COUNT(*) = COUNT(DISTINCT PRIMARY_CONDITION), 'PASS - unique key', 'FAIL - duplicates')
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.DIM_CONDITION
UNION ALL
SELECT 'AGG_FACILITY', COUNT(*), ROUND(SUM(BILLED)),
       IFF(COUNT(*) = 3918
           AND MIN(IFF(CUMULATIVE_PCT >= 50, SPEND_RANK, NULL)) = 86, 'PASS', 'CHECK')
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.AGG_FACILITY
UNION ALL
SELECT 'AGG_STATE', COUNT(*), ROUND(SUM(BILLED)),
       IFF(ROUND(SUM(BILLED)) = 99111300188, 'PASS', 'CHECK')
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.AGG_STATE
UNION ALL
SELECT 'AGG_CONCENTRATION', COUNT(*), CAST(NULL AS NUMBER),
       IFF(MAX(IFF(GRAIN = 'Facilities', ENTITIES_FOR_HALF, NULL)) = 86, 'PASS', 'CHECK')
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.AGG_CONCENTRATION
UNION ALL
SELECT 'AGG_LORENZ', COUNT(*), CAST(NULL AS NUMBER),
       IFF(COUNT(*) BETWEEN 190 AND 210, 'PASS', 'CHECK')
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.AGG_LORENZ;
