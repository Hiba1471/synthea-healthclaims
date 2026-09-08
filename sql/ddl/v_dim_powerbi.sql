-- =====================================================================
-- DIMENSION VIEWS FOR THE POWER BI MODEL
--
-- The aggregate views repeat CARE_TYPE, PAYER_TYPE and SERVICE_YEAR across
-- many rows each, so relating them to each other on those columns gives a
-- many-to-many relationship. Power BI allows it, it resolves without error,
-- and it silently returns wrong totals once you slice. These four views give
-- each key a table where it appears exactly once, so every relationship is a
-- clean one-to-many.
--
-- RELATIONSHIPS TO BUILD -- all One to many (1:*), cross-filter Single,
-- direction dimension -> fact:
--
--   DIM_CARE_TYPE[CARE_TYPE]    -> V_AGG_SPEND[CARE_TYPE]
--   DIM_CARE_TYPE[CARE_TYPE]    -> V_AGG_CONDITION[CARE_TYPE]
--   DIM_PAYER_TYPE[PAYER_TYPE]  -> V_AGG_SPEND[PAYER_TYPE]
--   DIM_PAYER_TYPE[PAYER_TYPE]  -> V_AGG_CONDITION[PAYER_TYPE]
--   DIM_YEAR[SERVICE_YEAR]      -> V_AGG_SPEND[SERVICE_YEAR]
--   DIM_YEAR[SERVICE_YEAR]      -> V_AGG_CONDITION[SERVICE_YEAR]
--   DIM_YEAR[SERVICE_YEAR]      -> V_AGG_FACILITY[SERVICE_YEAR]
--   DIM_FACILITY[FACILITY_KEY]  -> V_AGG_FACILITY[FACILITY_KEY]
--
-- Build every slicer from the DIM tables, never from a fact table. A slicer
-- built on V_AGG_SPEND[CARE_TYPE] filters that table only; the same slicer
-- built on DIM_CARE_TYPE filters both facts through the relationships.
--
-- LEAVE THESE THREE DISCONNECTED -- no relationships at all:
--   V_AGG_MEMBERS, V_MEMBER_OOP_PERCENTILES, V_SPEND_CONCENTRATION
-- Their measures filter themselves explicitly and they describe the whole
-- window. Relating them would invite Power BI to filter them by context they
-- have no meaningful response to.
--
-- WHY YEAR AND NOT A FULL DATE TABLE. V_AGG_CONDITION and V_AGG_FACILITY are
-- aggregated to the year; only V_AGG_SPEND carries a month. A month-grain
-- date dimension therefore cannot relate to all three. Year is the common
-- key, and the monthly page reads SERVICE_MONTH_START straight off
-- V_AGG_SPEND, which is the only table that page uses. If you later want a
-- month slicer driving every page, rebuild the condition and facility
-- aggregates at month grain and swap DIM_YEAR for a proper date table.
-- =====================================================================

CREATE OR REPLACE VIEW SYNTHEA_HEALTHCLAIMS.PUBLIC.DIM_CARE_TYPE AS
SELECT DISTINCT
    CARE_TYPE,
    -- lets a visual exclude the residual without hardcoding the string
    IFF(CARE_TYPE = 'No diagnosis on claim', FALSE, TRUE) AS IS_CLINICAL
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE;


CREATE OR REPLACE VIEW SYNTHEA_HEALTHCLAIMS.PUBLIC.DIM_PAYER_TYPE AS
SELECT DISTINCT PAYER_TYPE
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE;


CREATE OR REPLACE VIEW SYNTHEA_HEALTHCLAIMS.PUBLIC.DIM_YEAR AS
SELECT DISTINCT SERVICE_YEAR
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE;


CREATE OR REPLACE VIEW SYNTHEA_HEALTHCLAIMS.PUBLIC.DIM_FACILITY AS
SELECT
    COALESCE(FACILITY_NAME, '(no facility on record)')
        || ' | ' || COALESCE(FACILITY_CITY, '')
        || ', '  || COALESCE(FACILITY_STATE, '')  AS FACILITY_KEY,
    MAX(FACILITY_NAME)                            AS FACILITY_NAME,
    MAX(FACILITY_CITY)                            AS FACILITY_CITY,
    MAX(FACILITY_STATE)                           AS FACILITY_STATE
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
GROUP BY COALESCE(FACILITY_NAME, '(no facility on record)')
        || ' | ' || COALESCE(FACILITY_CITY, '')
        || ', '  || COALESCE(FACILITY_STATE, '');


-- =====================================================================
-- ACCEPTANCE CHECK. Every key must be unique, or the relationship will
-- refuse to be one-to-many. Duplicates here are the thing to fix.
-- =====================================================================
SELECT 'DIM_CARE_TYPE'  AS "Dimension", COUNT(*) AS "Rows",
       COUNT(DISTINCT CARE_TYPE) AS "Distinct keys",
       IFF(COUNT(*) = COUNT(DISTINCT CARE_TYPE), 'PASS - unique', 'FAIL - duplicate keys') AS "Result"
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.DIM_CARE_TYPE
UNION ALL
SELECT 'DIM_PAYER_TYPE', COUNT(*), COUNT(DISTINCT PAYER_TYPE),
       IFF(COUNT(*) = COUNT(DISTINCT PAYER_TYPE), 'PASS - unique', 'FAIL - duplicate keys')
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.DIM_PAYER_TYPE
UNION ALL
SELECT 'DIM_YEAR', COUNT(*), COUNT(DISTINCT SERVICE_YEAR),
       IFF(COUNT(*) = COUNT(DISTINCT SERVICE_YEAR), 'PASS - unique', 'FAIL - duplicate keys')
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.DIM_YEAR
UNION ALL
SELECT 'DIM_FACILITY', COUNT(*), COUNT(DISTINCT FACILITY_KEY),
       IFF(COUNT(*) = COUNT(DISTINCT FACILITY_KEY), 'PASS - unique', 'FAIL - duplicate keys')
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.DIM_FACILITY;
