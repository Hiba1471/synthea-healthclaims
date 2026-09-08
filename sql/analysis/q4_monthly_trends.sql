-- =====================================================================
-- MONTHLY TRENDS, 2020-2024, for the dashboard's Monthly Trends view.
--
-- Everything else in sql/results/ is aggregated to SERVICE_YEAR, so the
-- dashboard has only ever been able to show five points. This is the same
-- money at month grain: 60 points instead of 5.
--
-- Reads V_CLAIMS_TX_WITH_CARETYPE (sql/ddl/v_claims_tx_with_caretype.sql),
-- which already applies the scope every other analysis query uses:
--     NOT IS_ADMIN_NOISE_CODE AND PROCEDURECODE IS NOT NULL
-- so no predicate is repeated here. Do NOT add "BILLED_AMOUNT > 0" -- that
-- drops every PAYMENT row and zeroes the member-paid columns.
--
-- Long format (cut, segment) so one file serves all three dashboard filters,
-- the same shape as q2_who_pays.sql:
--     1. Overall     -- one row per month
--     2. Payer type  -- Commercial / Government / Self-Pay per month
--     3. Care type   -- one row per care type per month
-- Expect roughly 60 x 20 = ~1,200 rows.
--
-- RECONCILIATION. Summing "1. Overall" by calendar year must reproduce
-- q2_who_pays_by_year_2020_2024.csv exactly:
--     2020  billed 20,616,260,845   member paid 4,210,202,568
--     2021  billed 20,948,177,114   member paid 4,335,321,688
--     2022  billed 20,291,316,213   member paid 4,142,352,401
-- If it does not, the view's scope has drifted from the analysis scope.
--
-- NOTE ON "People affected": a member seen in several months is counted in
-- each of them, so this column does NOT sum down the rows to a headcount.
-- It is per-month distinct, which is what a monthly trend needs.
--
-- Save results to: sql/results/q4_monthly_trends_2020_2024.csv
-- =====================================================================

WITH base AS (
    SELECT
        SERVICE_MONTH_START,
        PAYER_TYPE,
        CARE_TYPE,
        PATIENT_ID,
        BILLED_AMOUNT,
        PAID_BY_PAYER,
        PAID_BY_PATIENT
    FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.V_CLAIMS_TX_WITH_CARETYPE
),
cuts AS (
    SELECT '1. Overall'    AS cut, 'All spend' AS segment, * FROM base
    UNION ALL
    SELECT '2. Payer type', PAYER_TYPE,                    * FROM base
    UNION ALL
    SELECT '3. Care type',  CARE_TYPE,                     * FROM base
)
SELECT
    cut                                                        AS "Cut",
    segment                                                    AS "Segment",
    TO_CHAR(SERVICE_MONTH_START, 'YYYY-MM')                    AS "Month",
    YEAR(SERVICE_MONTH_START)                                  AS "Year",
    MONTH(SERVICE_MONTH_START)                                 AS "Month number",
    ROUND(SUM(BILLED_AMOUNT))                                  AS "Total billed",
    ROUND(SUM(PAID_BY_PAYER))                                  AS "Paid by insurer",
    ROUND(SUM(PAID_BY_PATIENT))                                AS "Paid by members",
    ROUND(100 * SUM(PAID_BY_PATIENT)
          / NULLIF(SUM(PAID_BY_PAYER) + SUM(PAID_BY_PATIENT), 0), 1)
                                                               AS "% of the bill members pay",
    COUNT(DISTINCT PATIENT_ID)                                 AS "People affected",
    ROUND(SUM(BILLED_AMOUNT)
          / NULLIF(COUNT(DISTINCT PATIENT_ID), 0), 2)          AS "Billed per person",
    ROUND(SUM(PAID_BY_PATIENT)
          / NULLIF(COUNT(DISTINCT PATIENT_ID), 0), 2)          AS "Paid by the person"
FROM cuts
GROUP BY cut, segment, SERVICE_MONTH_START
ORDER BY cut, segment, SERVICE_MONTH_START;
