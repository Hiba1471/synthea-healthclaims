-- =====================================================================
-- AGG_STATE -- spend concentration by patient state, for Power BI.
--
-- Neither the analysis nor any existing table groups by PATIENT_STATE. This
-- is new, not a reformat of a published result -- there is no report figure
-- to reconcile against, only the acceptance total ($99,111,300,188) and the
-- membership total (1,259,375).
--
-- Grain: one row per PATIENT_STATE, whole 2020-2024 window. Add SERVICE_YEAR
-- to the GROUP BY if you want it sliceable by year later.
--
-- Rank and cumulative % are precomputed the same way as AGG_FACILITY, so
-- Power BI reads a column instead of running an O(n^2) ranking pattern.
-- =====================================================================

CREATE OR REPLACE TABLE SYNTHEA_HEALTHCLAIMS.PUBLIC.AGG_STATE AS
SELECT
    COALESCE(PATIENT_STATE, '(no state on record)')            AS PATIENT_STATE,
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


-- =====================================================================
-- ACCEPTANCE CHECK. Billed must total 99,111,300,188 and members 1,259,375
-- -- summing across states must not lose or duplicate anyone.
--
-- Also prints how many states exist and how concentrated spend is by state,
-- since neither is known yet. If nearly all states are Ohio-adjacent
-- (Cleveland/Chicago/Detroit per the report's own client profile), a small
-- handful of states will carry almost everything -- that is expected, not a
-- bug, and worth stating on the chart rather than treating as a discovery.
-- =====================================================================
SELECT
    COUNT(*)                                                    AS "States",
    ROUND(SUM(BILLED))                                          AS "Billed",
    SUM(MEMBERS)                                                AS "Members summed (NOT a real headcount)",
    MIN(IFF(CUMULATIVE_PCT >= 50, SPEND_RANK, NULL))            AS "States for half of spend",
    MIN(IFF(CUMULATIVE_PCT >= 90, SPEND_RANK, NULL))            AS "States for 90% of spend",
    IFF(ROUND(SUM(BILLED)) = 99111300188, 'PASS', 'CHECK')      AS "Result"
FROM SYNTHEA_HEALTHCLAIMS.PUBLIC.AGG_STATE;

-- The "Members summed" column above is deliberately mislabelled as a warning:
-- a member seen in one state only is fine, but if Synthea ever moves a
-- patient's recorded state across encounters, summing MEMBERS across states
-- would overcount them the same way summing across care types does. Check
-- this figure against 1,259,375 before trusting any member-based state
-- measure; if it is materially higher, MEMBERS here needs the same
-- long-format treatment AGG_MEMBERS already gets.
