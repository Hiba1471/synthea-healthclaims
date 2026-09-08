-- =====================================================================
-- AGGREGATE VIEWS FOR POWER BI IMPORT
--
-- Written against the columns V_CLAIMS_TX_WITH_CARETYPE actually exposes:
--
--   CLAIMS_TX_ID, CLAIM_ID, PATIENT_ID, ENCOUNTER_ID,
--   BILLED_AMOUNT, PAID_AMOUNT, PAID_BY_PAYER, PAID_BY_PATIENT,
--   PAYER_NAME, PAYER_TYPE,
--   FROMDATE, SERVICE_YEAR, SERVICE_MONTH, SERVICE_MONTH_START, SERVICE_QUARTER,
--   PROCEDURECODE, ENCOUNTERCLASS, ENCOUNTER_START,
--   PRIMARY_CONDITION, CARE_TYPE,
--   PATIENT_STATE, FACILITY_NAME, FACILITY_CITY, FACILITY_STATE
--
-- WHY THESE EXIST. The dashboard never shows a transaction line -- it shows
-- totals by month, payer, care type, condition and facility. Importing those
-- totals instead of 68.6M lines lifts every DirectQuery restriction at once:
-- MEDIAN works again, the model fits inside the 1GB Pro limit, and touching a
-- slicer stops firing a dozen queries at Snowflake.
--
--   V_AGG_SPEND       month x payer type x care type      ~2,900 rows
--   V_AGG_CONDITION   year x payer type x condition       ~2,800 rows
--   V_AGG_FACILITY    year x facility                    ~19,600 rows
--   V_AGG_MEMBERS     distinct member counts, long form      ~25 rows
--
-- Set all four to Import storage mode.
--
-- ---------------------------------------------------------------------
-- RULE 1: MONEY ADDS UP, MEMBERS DO NOT.
--
-- BILLED_AMOUNT, PAID_AMOUNT, PAID_BY_PAYER and PAID_BY_PATIENT are additive,
-- which is what makes pre-aggregating them safe at all.
--
-- COUNT(DISTINCT PATIENT_ID) is not. A member with a dental claim and a
-- maternity claim is counted once in each care type, so adding the care-type
-- counts together roughly doubles the true headcount. Every member column
-- below is named MEMBERS_AT_GRAIN and is correct ONLY on its own row. Set its
-- Power BI summarization to "Don't summarize", and read real headcounts from
-- V_AGG_MEMBERS.
--
-- ---------------------------------------------------------------------
-- RULE 2: THE FACILITY KEY.
--
-- The published figure -- 86 of 3,918 facilities carry half of spend -- comes
-- from q3_concentration.sql, which groups by ENCOUNTERS.ORGANIZATION_ID. This
-- view does not expose that column, so V_AGG_FACILITY below groups by
-- FACILITY_NAME + FACILITY_CITY + FACILITY_STATE, the same composite key
-- q3_top_entities.sql uses to identify a site.
--
-- Grouping by FACILITY_NAME ALONE is what returns 65 instead of 86: names are
-- not unique across sites, and rows whose organisation did not match the join
-- collapse into a single blank bucket that ranks near the top.
--
-- The composite key is close to ORGANIZATION_ID but not guaranteed identical.
-- If the acceptance check does not return 3,918 sites, add the real key to
-- V_CLAIMS_TX_WITH_CARETYPE -- one line, in the geography block:
--
--     enc.ORGANIZATION_ID  AS FACILITY_ID,
--
-- then group this view by FACILITY_ID instead. That is the only way to
-- reproduce the published count exactly.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. V_AGG_SPEND -- the workhorse. Serves the KPI strip, the gauge, the
--    donut, the care-type bars, plan-type-by-year and monthly trends.
--    Rolls up to year, quarter, payer or care type by simple SUM.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW SYNTHEA_HEALTHCLAIMS.PUBLIC.V_AGG_SPEND AS
SELECT
    SERVICE_MONTH_START,
    SERVICE_YEAR,
    SERVICE_QUARTER,
    SERVICE_MONTH,
    PAYER_TYPE,
    CARE_TYPE,
    SUM(BILLED_AMOUNT)                         AS BILLED,
    SUM(PAID_AMOUNT)                           AS PAID_TOTAL,
    SUM(PAID_BY_PAYER)                         AS PAID_BY_INSURER,
    SUM(PAID_BY_PATIENT)                       AS PAID_BY_MEMBERS,
    COUNT(DISTINCT CLAIM_ID)                   AS CLAIMS,
    COUNT(DISTINCT PATIENT_ID)                 AS MEMBERS_AT_GRAIN   -- do not sum
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
GROUP BY SERVICE_MONTH_START, SERVICE_YEAR, SERVICE_QUARTER,
         SERVICE_MONTH, PAYER_TYPE, CARE_TYPE;


-- ---------------------------------------------------------------------
-- 2. V_AGG_CONDITION -- the care-type drill-down.
--    CARE_TYPE is carried alongside so the drill hierarchy needs no join.
--    Covers diagnosed spend only (~$72.69B), because a claim with no
--    resolvable diagnosis has no condition to group by.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW SYNTHEA_HEALTHCLAIMS.PUBLIC.V_AGG_CONDITION AS
SELECT
    SERVICE_YEAR,
    PAYER_TYPE,
    CARE_TYPE,
    PRIMARY_CONDITION,
    SUM(BILLED_AMOUNT)                         AS BILLED,
    SUM(PAID_AMOUNT)                           AS PAID_TOTAL,
    SUM(PAID_BY_PAYER)                         AS PAID_BY_INSURER,
    SUM(PAID_BY_PATIENT)                       AS PAID_BY_MEMBERS,
    COUNT(DISTINCT PATIENT_ID)                 AS MEMBERS_AT_GRAIN   -- do not sum
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
WHERE PRIMARY_CONDITION IS NOT NULL
GROUP BY SERVICE_YEAR, PAYER_TYPE, CARE_TYPE, PRIMARY_CONDITION;


-- ---------------------------------------------------------------------
-- 3. V_AGG_FACILITY -- the concentration page and any geography visual.
--    Keyed on name + city + state (see RULE 2 above), with FACILITY_KEY
--    provided as a single field to group and count on in Power BI.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW SYNTHEA_HEALTHCLAIMS.PUBLIC.V_AGG_FACILITY AS
SELECT
    SERVICE_YEAR,
    COALESCE(FACILITY_NAME, '(no facility on record)')
        || ' | ' || COALESCE(FACILITY_CITY, '')
        || ', '  || COALESCE(FACILITY_STATE, '')  AS FACILITY_KEY,
    FACILITY_NAME,
    FACILITY_CITY,
    FACILITY_STATE,
    SUM(BILLED_AMOUNT)                         AS BILLED,
    SUM(PAID_BY_PATIENT)                       AS PAID_BY_MEMBERS,
    COUNT(DISTINCT ENCOUNTER_ID)               AS ENCOUNTERS,
    COUNT(DISTINCT PATIENT_ID)                 AS MEMBERS_AT_GRAIN   -- do not sum
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
GROUP BY SERVICE_YEAR, FACILITY_NAME, FACILITY_CITY, FACILITY_STATE;


-- ---------------------------------------------------------------------
-- 4. V_AGG_MEMBERS -- distinct headcounts, precomputed per grain.
--    Read a value from here; never add MEMBERS_AT_GRAIN across rows above.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW SYNTHEA_HEALTHCLAIMS.PUBLIC.V_AGG_MEMBERS AS
SELECT 'Total' AS GRAIN, 'All members' AS SEGMENT,
       COUNT(DISTINCT PATIENT_ID) AS MEMBERS
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
UNION ALL
SELECT 'Year', TO_VARCHAR(SERVICE_YEAR), COUNT(DISTINCT PATIENT_ID)
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
GROUP BY SERVICE_YEAR
UNION ALL
SELECT 'Payer type', PAYER_TYPE, COUNT(DISTINCT PATIENT_ID)
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
GROUP BY PAYER_TYPE
UNION ALL
SELECT 'Care type', CARE_TYPE, COUNT(DISTINCT PATIENT_ID)
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
GROUP BY CARE_TYPE;


-- =====================================================================
-- ACCEPTANCE CHECK. Run after creating all four.
--
--   V_AGG_SPEND      billed 99,111,300,188   members paid 20,256,370,607
--   V_AGG_FACILITY   billed 99,111,300,188   sites 3,918
--   V_AGG_CONDITION  billed ~72.69B  (diagnosed spend only -- expected)
--   V_AGG_MEMBERS    total 1,259,375
--
-- If "Distinct sites" is not 3,918, the composite facility key is not
-- resolving to the same entities as ORGANIZATION_ID -- see RULE 2.
-- =====================================================================
SELECT 'V_AGG_SPEND'                                       AS "View",
       ROUND(SUM(BILLED))                                  AS "Total billed",
       ROUND(SUM(PAID_BY_MEMBERS))                         AS "Paid by members",
       NULL                                                AS "Distinct sites",
       IFF(ROUND(SUM(BILLED)) = 99111300188, 'PASS', 'CHECK') AS "Result"
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_AGG_SPEND
UNION ALL
SELECT 'V_AGG_CONDITION',
       ROUND(SUM(BILLED)), ROUND(SUM(PAID_BY_MEMBERS)), NULL,
       IFF(ROUND(SUM(BILLED)) BETWEEN 72600000000 AND 72800000000,
           'PASS - diagnosed spend only', 'CHECK')
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_AGG_CONDITION
UNION ALL
SELECT 'V_AGG_FACILITY',
       ROUND(SUM(BILLED)), ROUND(SUM(PAID_BY_MEMBERS)),
       COUNT(DISTINCT FACILITY_KEY),
       IFF(ROUND(SUM(BILLED)) = 99111300188
           AND COUNT(DISTINCT FACILITY_KEY) = 3918, 'PASS',
           'CHECK - see RULE 2 on the facility key')
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_AGG_FACILITY
UNION ALL
SELECT 'V_AGG_MEMBERS', NULL, NULL, NULL,
       IFF(MAX(IFF(GRAIN = 'Total', MEMBERS, NULL)) = 1259375, 'PASS', 'CHECK')
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_AGG_MEMBERS;
