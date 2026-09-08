-- =====================================================================
-- YEAR AND PAYER-YEAR AGGREGATES FOR POWER BI
--
--   V_AGG_BY_YEAR         5 rows   -- the spending trend chart
--   V_AGG_BY_PAYER_YEAR  15 rows   -- member-paid share by payer type
--
-- WHY THESE EXIST WHEN V_AGG_SPEND ALREADY ROLLS UP.
--
-- The money columns in V_AGG_SPEND are additive, so billed and member-paid by
-- year can be had by summing it. The MEMBER COUNTS cannot. A member appears in
-- several months, several care types and possibly several payer types, so
-- SUM(MEMBERS_AT_GRAIN) over those rows double-counts them -- by roughly a
-- factor of two at the year level, and worse at the total.
--
-- These two views compute COUNT(DISTINCT PATIENT_ID) at their own grain, so
-- the headcount is correct without any DAX gymnastics, and cost-per-member
-- becomes a plain division that is right at every row.
--
-- Both are small enough to import with no meaningful cost.
--
-- ONE THING THAT STILL DOES NOT ADD UP. The member counts in
-- V_AGG_BY_PAYER_YEAR do not sum to the counts in V_AGG_BY_YEAR: a member
-- covered by both commercial and government plans in the same year is counted
-- in each. That is correct at each grain and wrong if added. Read each view at
-- its own grain; never sum a member column.
--
-- Denominator note: "% of the bill members pay" is member-paid over total
-- PAID, matching q2_who_pays.sql. In this dataset collection is 100% so it
-- coincides with billed, but the paid-based figure is the one that survives
-- contact with real claims.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. V_AGG_BY_YEAR -- the spending trend chart.
--
--    Expected, from sql/results/q2_who_pays_by_year_2020_2024.csv:
--      2020  billed 20,616,260,845  members paid 4,210,202,568  20.4%  1,137,017
--      2021  billed 20,948,177,114  members paid 4,335,321,688  20.7%  1,192,975
--      2022  billed 20,291,316,213  members paid 4,142,352,401  20.4%  1,143,226
--      2023  billed 20,441,952,993  members paid 4,158,872,837  20.3%  1,149,845
--      2024  billed 16,813,593,023  members paid 3,409,621,113  20.3%  1,074,995
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW SYNTHEA_HEALTHCLAIMS.PUBLIC.V_AGG_BY_YEAR AS
SELECT
    SERVICE_YEAR,
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
          / NULLIF(COUNT(DISTINCT CLAIM_ID), 0), 2)             AS AVG_COST_PER_CLAIM
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
GROUP BY SERVICE_YEAR;


-- ---------------------------------------------------------------------
-- 2. V_AGG_BY_PAYER_YEAR -- member-paid share by payer type over time.
--
--    Expected share, from the same source:
--      Commercial            29.7 / 30.2 / 30.0 / 30.0 / 30.0
--      Government             2.6 /  2.8 /  2.6 /  2.6 /  2.7
--      Self-Pay / Uninsured 100.0 across all five years, by definition --
--        there is no insurer to carry any part of the bill.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW SYNTHEA_HEALTHCLAIMS.PUBLIC.V_AGG_BY_PAYER_YEAR AS
SELECT
    SERVICE_YEAR,
    PAYER_TYPE,
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
          / NULLIF(COUNT(DISTINCT PATIENT_ID), 0), 2)           AS MEMBER_PAID_PER_MEMBER
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
GROUP BY SERVICE_YEAR, PAYER_TYPE;


-- =====================================================================
-- ACCEPTANCE CHECK. Both views must reproduce
-- sql/results/q2_who_pays_by_year_2020_2024.csv to the dollar.
--
-- The two views deliberately disagree on member counts -- summing the payer
-- rows gives more members than the year row, because a member covered by two
-- plan types in one year is counted in each. That is expected. The BILLED
-- totals must match exactly.
-- =====================================================================
WITH yr AS (
    SELECT SERVICE_YEAR, BILLED, PAID_BY_MEMBERS, MEMBER_PAID_SHARE_PCT, MEMBERS
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_AGG_BY_YEAR
),
py AS (
    SELECT SERVICE_YEAR, SUM(BILLED) AS BILLED, SUM(PAID_BY_MEMBERS) AS PAID_BY_MEMBERS
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_AGG_BY_PAYER_YEAR
    GROUP BY SERVICE_YEAR
),
expected AS (
    SELECT * FROM VALUES
        (2020, 20616260845, 4210202568, 20.4, 1137017),
        (2021, 20948177114, 4335321688, 20.7, 1192975),
        (2022, 20291316213, 4142352401, 20.4, 1143226),
        (2023, 20441952993, 4158872837, 20.3, 1149845),
        (2024, 16813593023, 3409621113, 20.3, 1074995)
    AS t(yr, billed, member_paid, share, members)
)
SELECT
    e.yr                                                        AS "Year",
    CASE
        WHEN ROUND(y.BILLED)          <> e.billed      THEN 'FAIL - billed'
        WHEN ROUND(y.PAID_BY_MEMBERS) <> e.member_paid THEN 'FAIL - member paid'
        WHEN ABS(y.MEMBER_PAID_SHARE_PCT - e.share) > 0.05 THEN 'FAIL - share'
        WHEN y.MEMBERS                <> e.members     THEN 'FAIL - member count'
        WHEN ROUND(p.BILLED)          <> e.billed      THEN 'FAIL - payer split does not reconcile'
        ELSE 'PASS'
    END                                                         AS "Result",
    e.billed                                                    AS "Billed, expected",
    ROUND(y.BILLED)                                             AS "Billed, by year",
    ROUND(p.BILLED)                                             AS "Billed, payer rows summed",
    e.members                                                   AS "Members, expected",
    y.MEMBERS                                                   AS "Members, by year"
FROM expected e
LEFT JOIN yr y ON y.SERVICE_YEAR = e.yr
LEFT JOIN py p ON p.SERVICE_YEAR = e.yr
ORDER BY e.yr;
